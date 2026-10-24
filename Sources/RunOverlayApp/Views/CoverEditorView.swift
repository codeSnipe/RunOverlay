import AppKit
import CoreText
import CoreGraphics
import ImageIO
import RunOverlayCore
import SwiftUI
import UniformTypeIdentifiers

struct CoverEditorView: View {
    @EnvironmentObject private var appModel: AppModel
    let videoID: UUID

    @State private var cover: VideoCover?
    @State private var baseImage: CGImage?
    @State private var previewBase: CGImage?
    @State private var renderedImage: CGImage?
    @State private var stationaryImage: CGImage?
    @State private var followingImage: CGImage?
    @State private var selectedTextImage: CGImage?
    @State private var visibleTextMask: CGImage?
    @State private var cachedLayer: CoverTextLayer?
    @State private var peopleAnalysis: CoverPeopleAnalysis?
    @State private var selectedLayerID: UUID?
    @State private var isLoading = false
    @State private var isExportingCover = false
    @State private var isPickingPeople = false
    @State private var message: String?
    @State private var revision = 0
    @State private var renderLoop: Task<Void, Never>?
    @State private var renderedRevision = -1
    @State private var imageLoadVersion = 0
    @State private var canvasGesture = CanvasGestureState()
    @State private var centerSnapGuides = (horizontal: false, vertical: false)
    @State private var hoveredCursor: NSCursor?
    @State private var isFontPickerPresented = false
    @State private var fontSearchText = ""
    @State private var fontFilter: CoverFontFilter = .chinese
    /// 拖动期间的图层副本：只更新本地状态，松手才写回模型，
    /// 避免每个拖动事件都触发全局模型发布和整窗重渲染。
    @State private var liveLayer: CoverTextLayer?

    private var selectedLayer: CoverTextLayer? {
        if let liveLayer, liveLayer.id == selectedLayerID {
            return liveLayer
        }
        return cover?.textLayers.first { $0.id == selectedLayerID }
    }

    private var people: [CoverPerson] {
        peopleAnalysis?.people ?? []
    }

    private func frameSource(at position: TimeInterval) -> CoverSource? {
        guard let video = appModel.project.videos.first(where: { $0.id == videoID }) else {
            return nil
        }
        let plan = appModel.outputPlan(for: video)
        return .videoFrame(CoverVideoFrame(
            seconds: position,
            includesDataLayer: appModel.snapshotIncludesDataLayer,
            aspectRatio: plan.aspectRatio,
            maximumHeight: plan.shortEdge,
            rotation: video.rotation
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            EditorTheme.separator.frame(height: 1)
            HStack(spacing: 0) {
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                EditorTheme.separator.frame(width: 1)
                properties
                    .frame(width: 330)
            }
            statusBar
        }
        .background(EditorTheme.canvas)
        .onAppear {
            // 先注册内置字体，再读取已保存的文字图层并开始预览渲染。
            _ = CoverEditorFontLibrary.fontNames
            loadInitialCover()
            startRenderLoop()
        }
        .onDisappear {
            renderLoop?.cancel()
            renderLoop = nil
            liveLayer = nil
            centerSnapGuides = (false, false)
            setHoverCursor(nil)
            appModel.flushCoverAutoSave()
        }
        .onChange(of: selectedLayerID) { _, _ in
            revision += 1
        }
        .onChange(of: appModel.cover(for: videoID)) { _, latest in
            guard let latest, latest != cover else { return }
            let sourceChanged = latest.source != cover?.source
            cover = latest
            if let selectedLayerID,
               !latest.textLayers.contains(where: { $0.id == selectedLayerID }) {
                self.selectedLayerID = latest.textLayers.first?.id
            }
            if sourceChanged, baseImage != nil, !isLoading {
                loadImage()
            } else if baseImage != nil {
                revision += 1
            }
        }
    }

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(EditorTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppStrings.text("ui.cover.title"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(EditorTheme.text)
                    Text(appModel.project.videos.first(where: { $0.id == videoID })?
                        .fileName ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(EditorTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 16)
                Button {
                    addText()
                } label: {
                    Label(AppStrings.text("ui.cover.addText"), systemImage: "text.badge.plus")
                        .frame(minWidth: 128)
                }
                .buttonStyle(CoverEditorButtonStyle(tone: .secondary))
                .disabled(cover == nil)
                Button {
                    exportCover()
                } label: {
                    Label(AppStrings.text("ui.cover.export"), systemImage: "square.and.arrow.up")
                        .frame(minWidth: 152)
                }
                .buttonStyle(CoverEditorButtonStyle(tone: .primary))
                .disabled(baseImage == nil || isLoading || isExportingCover)
            }
            .padding(.horizontal, 20)
            .frame(height: 82)

            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    sourceButton(
                        "ui.cover.currentFrame",
                        symbol: "video",
                        isSelected: isCurrentFrameSource,
                        action: chooseCurrentFrame
                    )
                    sourceButton(
                        "ui.cover.importImage",
                        symbol: "photo.on.rectangle",
                        isSelected: isImportedImageSource,
                        action: chooseImage
                    )
                }
                .padding(4)
                .background(
                    EditorTheme.surface,
                    in: RoundedRectangle(cornerRadius: 11)
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .background(EditorTheme.sidebar)
    }

    private var isCurrentFrameSource: Bool {
        if case .videoFrame? = cover?.source { return true }
        return false
    }

    private var isImportedImageSource: Bool {
        if case .image? = cover?.source { return true }
        return false
    }

    private func sourceButton(
        _ title: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(AppStrings.text(title), systemImage: symbol)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? EditorTheme.text : EditorTheme.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .frame(width: 180)
        .buttonStyle(EditorChoiceTabButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(message == nil ? EditorTheme.accent : EditorTheme.highlight)
                .frame(width: 6, height: 6)
            Text(message ?? AppStrings.text("ui.cover.statusReady"))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 10)
            if let image = previewBase {
                Text("\(image.width) × \(image.height)")
                    .monospacedDigit()
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(EditorTheme.muted)
        .padding(.horizontal, 18)
        .frame(height: 30)
        .background(EditorTheme.sidebar)
        .overlay(alignment: .top) {
            EditorTheme.separator.frame(height: 1)
        }
    }

    private var canvas: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(EditorTheme.accent)
                    .frame(width: 6, height: 6)
                Text(AppStrings.text("ui.cover.preview"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EditorTheme.text)
                Spacer()
                Text(AppStrings.text("ui.cover.canvasHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(EditorTheme.muted)
            }
            GeometryReader { proxy in
                ZStack {
                    Color.black.opacity(0.75)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !isPickingPeople else { return }
                            clearSelectedLayer()
                        }
                    if let image = dragDisplayImage ?? renderedImage ?? previewBase {
                        let size = fittedSize(
                            source: CGSize(width: image.width, height: image.height),
                            available: proxy.size
                        )
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: size.width, height: size.height)
                            .overlay {
                                liveTextOverlay(size: size)
                            }
                            .overlay {
                                followingLayersOverlay(size: size)
                            }
                            .overlay {
                                personSelectionOverlay(size: size)
                            }
                            .overlay {
                                centerAlignmentGuides(size: size)
                            }
                            .overlay {
                                selectionFrameOverlay(size: size)
                            }
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    updateHoverCursor(at: location, size: size)
                                case .ended:
                                    setHoverCursor(nil)
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        handleCanvasChange(value, size: size)
                                    }
                                    .onEnded { value in
                                        handleCanvasEnd(value, size: size)
                                    }
                            )
                    } else if isLoading {
                        ProgressView(AppStrings.text("ui.cover.loading"))
                    } else {
                        VStack(spacing: 11) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 28, weight: .ultraLight))
                            Text(AppStrings.text("ui.cover.empty"))
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(EditorTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 9))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            HStack(spacing: 7) {
                Image(systemName: "hand.draw")
                Text(AppStrings.text("ui.cover.dragHint"))
                Text("·")
                Text(AppStrings.text("ui.cover.rotateHint"))
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .foregroundStyle(EditorTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dragDisplayImage: CGImage? {
        guard let liveLayer,
              cachedLayer?.id == liveLayer.id,
              selectedTextImage != nil else { return nil }
        return stationaryImage
    }

    @ViewBuilder
    private func followingLayersOverlay(size: CGSize) -> some View {
        if dragDisplayImage != nil, let followingImage {
            Image(decorative: followingImage, scale: 1)
                .resizable()
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func liveTextOverlay(size: CGSize) -> some View {
        if let liveLayer, let cachedLayer,
           cachedLayer.id == liveLayer.id,
           let selectedTextImage, stationaryImage != nil {
            let scale = liveLayer.fontHeight / max(cachedLayer.fontHeight, 0.001)
            let delta = liveLayer.rotationDegrees - cachedLayer.rotationDegrees
            let canvasCenter = CGPoint(x: size.width / 2, y: size.height / 2)
            let cachedFrame = CoverComposer().textFrame(
                of: cachedLayer,
                imageSize: size
            )
            let liveFrame = CoverComposer().textFrame(
                of: liveLayer,
                imageSize: size
            )
            let cachedCenter = CGPoint(
                x: cachedFrame.midX * size.width,
                y: cachedFrame.midY * size.height
            )
            let rotatedCenter = CoverCanvasGeometry.rotate(
                cachedCenter,
                around: canvasCenter,
                degrees: delta
            )
            let x = liveFrame.midX * size.width -
                canvasCenter.x - (rotatedCenter.x - canvasCenter.x) * scale
            let y = liveFrame.midY * size.height -
                canvasCenter.y - (rotatedCenter.y - canvasCenter.y) * scale
            let text = Image(decorative: selectedTextImage, scale: 1)
                .resizable()
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .rotationEffect(.degrees(delta))
                .offset(x: x, y: y)
            if let visibleTextMask {
                text.mask {
                    Image(decorative: visibleTextMask, scale: 1)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                }
                .allowsHitTesting(false)
            } else {
                text.allowsHitTesting(false)
            }
        }
    }

    private var properties: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                layerList
                if let layer = selectedLayer {
                    typographyControls
                    appearanceControls
                    occlusionControls(for: layer)
                    Button(role: .destructive) {
                        removeSelectedLayer()
                    } label: {
                        Label(AppStrings.text("ui.cover.deleteText"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CoverEditorButtonStyle(tone: .destructive))
                } else {
                    Text(AppStrings.text("ui.cover.selectLayerHint"))
                        .font(.system(size: 12))
                        .foregroundStyle(EditorTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 18)
                }
                if let export = appModel.cover(for: videoID)?.exportedImage {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            appModel.resolveCoverResource(export)
                        ])
                    } label: {
                        Label(AppStrings.text("ui.cover.showExport"), systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CoverEditorButtonStyle(tone: .secondary))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
        }
        .background(EditorTheme.sidebar)
    }

    private var layerList: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("ui.cover.layers", symbol: "square.3.layers.3d")
            if let cover, !cover.textLayers.isEmpty {
                ForEach(cover.textLayers) { layer in
                    let isSelected = selectedLayerID == layer.id
                    HStack(spacing: 8) {
                        Button {
                            selectedLayerID = layer.id
                            isPickingPeople = false
                        } label: {
                            HStack(spacing: 10) {
                                Text("Aa")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .frame(width: 36, height: 36)
                                    .background(
                                        isSelected
                                            ? EditorTheme.accent.opacity(0.18)
                                            : EditorTheme.surface,
                                        in: RoundedRectangle(cornerRadius: 7)
                                    )
                                Text(layer.text.isEmpty ? "…" : layer.text)
                                    .font(.system(
                                        size: 13,
                                        weight: isSelected ? .semibold : .medium
                                    ))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                            }
                            .foregroundStyle(isSelected ? EditorTheme.accent : EditorTheme.muted)
                            .padding(.horizontal, 10)
                        }
                        .buttonStyle(CoverEditorButtonStyle(
                            tone: .layer,
                            isSelected: isSelected
                        ))
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])

                        Button {
                            duplicateTextLayer(id: layer.id)
                        } label: {
                            Image(systemName: "plus.square.on.square")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(EditorActionButtonStyle(tone: .quiet, size: .icon))
                        .help(AppStrings.text("ui.cover.duplicateText"))
                        .accessibilityLabel(AppStrings.text("ui.cover.duplicateText"))
                    }
                }
            } else {
                Text(AppStrings.text("ui.cover.noLayers"))
                    .font(.system(size: 12))
                    .foregroundStyle(EditorTheme.muted)
                    .padding(.vertical, 11)
            }
        }
    }

    private var typographyControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("ui.cover.typography", symbol: "textformat")
            labeledControl("ui.cover.text") {
                TextField(AppStrings.text("ui.cover.text"), text: layerBinding(\.text))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 11)
                    .frame(height: 35)
                    .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 7))
            }
            labeledControl("ui.cover.font") {
                Button {
                    fontSearchText = ""
                    fontFilter = .chinese
                    isFontPickerPresented = true
                } label: {
                    HStack(spacing: 10) {
                        fontPreview(selectedLayer?.fontName ?? "")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fontDisplayName(selectedLayer?.fontName ?? ""))
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(selectedLayer?.fontName ?? "")
                                .font(.system(size: 10))
                                .foregroundStyle(EditorTheme.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CoverEditorButtonStyle(tone: .secondary))
                .popover(
                    isPresented: $isFontPickerPresented,
                    arrowEdge: .leading
                ) {
                    fontPicker
                }
            }
            HStack(spacing: 8) {
                fontTraitButton(
                    title: "ui.cover.bold",
                    symbol: "bold",
                    isSelected: selectedLayer?.isBold ?? false
                ) {
                    updateSelectedLayer { $0.isBold.toggle() }
                }
                fontTraitButton(
                    title: "ui.cover.italic",
                    symbol: "italic",
                    isSelected: selectedLayer?.isItalic ?? false
                ) {
                    updateSelectedLayer { $0.isItalic.toggle() }
                }
            }
            slider(
                title: "ui.cover.size",
                value: layerBinding(\.fontHeight),
                in: CoverTextLayer.fontHeightRange
            )
            HStack(spacing: 10) {
                Text(AppStrings.text("ui.cover.rotation"))
                    .font(.system(size: 11))
                    .foregroundStyle(EditorTheme.muted)
                    .frame(width: 45, alignment: .leading)
                Slider(
                    value: layerBinding(\.rotationDegrees),
                    in: -180...180
                )
                .tint(EditorTheme.accent)
                .accessibilityLabel(AppStrings.text("ui.cover.rotation"))
                TextField(
                    AppStrings.text("ui.cover.rotation"),
                    value: layerBinding(\.rotationDegrees),
                    format: .number.precision(.fractionLength(0))
                )
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 33)
                Text("°")
                    .foregroundStyle(EditorTheme.muted)
            }
        }
    }

    private func fontTraitButton(
        title: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(AppStrings.text(title), systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(CoverEditorButtonStyle(tone: .font, isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var fontPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.text("ui.cover.font"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EditorTheme.text)
            TextField(
                AppStrings.text("ui.cover.fontSearch"),
                text: $fontSearchText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 9))
            HStack(spacing: 0) {
                fontFilterTab(.chinese)
                fontFilterTab(.all)
            }
            .padding(3)
            .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredFonts, id: \.self) { name in
                        Button {
                            updateSelectedLayer { layer in
                                layer.fontName = name
                                let traits = CTFontGetSymbolicTraits(
                                    CTFontCreateWithName(name as CFString, 12, nil)
                                )
                                layer.isBold = traits.contains(.traitBold)
                                layer.isItalic = traits.contains(.traitItalic)
                            }
                            isFontPickerPresented = false
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fontDisplayName(name))
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    if CoverEditorFontLibrary.chineseFontNames.contains(name) {
                                        Text(name)
                                            .font(.system(size: 10))
                                            .foregroundStyle(EditorTheme.muted)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                Spacer()
                                fontPreview(name)
                                if selectedLayer?.fontName == name {
                                    Image(systemName: "checkmark")
                                        .frame(width: 12)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CoverEditorButtonStyle(
                            tone: .font,
                            isSelected: selectedLayer?.fontName == name
                        ))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 290, height: 355)
        .background(EditorTheme.sidebar)
    }

    private func fontFilterTab(_ filter: CoverFontFilter) -> some View {
        let isSelected = fontFilter == filter
        return Button {
            fontFilter = filter
        } label: {
            Text(AppStrings.text(filter == .chinese
                ? "ui.cover.chineseFonts" : "ui.cover.allFonts"))
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? EditorTheme.text : EditorTheme.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(EditorChoiceTabButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func fontDisplayName(_ name: String) -> String {
        CoverEditorFontLibrary.displayName(for: name)
    }

    private func fontPreview(_ name: String) -> some View {
        Text("字体")
            .font(.custom(name, size: 18))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 45)
            .layoutPriority(1)
            .accessibilityHidden(true)
    }

    private var filteredFonts: [String] {
        CoverEditorFontLibrary.filteredNames(
            search: fontSearchText,
            chineseOnly: fontFilter == .chinese,
            including: selectedLayer?.fontName
        )
    }

    private var appearanceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("ui.cover.appearance", symbol: "paintpalette")
            Text(AppStrings.text("ui.cover.recommendedColors"))
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.muted)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5),
                spacing: 7
            ) {
                ForEach(CoverTextColorPreset.recommendations) { preset in
                    let isSelected = selectedLayer?.colorHex == preset.textHex &&
                        selectedLayer?.strokeHex == preset.strokeHex
                    Button {
                        updateSelectedLayer { $0.apply(preset) }
                    } label: {
                        colorPresetPreview(preset, layer: selectedLayer)
                        .frame(maxWidth: .infinity)
                        .frame(height: 51)
                    }
                    .buttonStyle(CoverEditorButtonStyle(
                        tone: .palette,
                        isSelected: isSelected
                    ))
                    .help("\(preset.textHex) / \(preset.strokeHex)")
                    .accessibilityLabel(AppStrings.format(
                        "ui.cover.presetLabel",
                        preset.id,
                        preset.textHex,
                        preset.strokeHex
                    ))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            colorControl("ui.cover.color", keyPath: \.colorHex)
            colorControl("ui.cover.strokeColor", keyPath: \.strokeHex)
            slider(
                title: "ui.cover.strokeWidth",
                value: layerBinding(\.strokeWidth),
                in: 0...0.12
            )
            slider(
                title: "ui.cover.shadow",
                value: layerBinding(\.shadowOpacity),
                in: 0...1
            )
        }
    }

    @ViewBuilder
    private func colorPresetPreview(
        _ preset: CoverTextColorPreset,
        layer: CoverTextLayer?
    ) -> some View {
        if let image = CoverEditorPalettePreview.image(for: preset, layer: layer) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 37)
                .accessibilityHidden(true)
        } else {
            Text("示例")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(coverHex: preset.textHex))
                .frame(maxWidth: .infinity)
                .frame(height: 37)
                .accessibilityHidden(true)
        }
    }

    private func colorControl(
        _ title: String,
        keyPath: WritableKeyPath<CoverTextLayer, String>
    ) -> some View {
        let color = colorBinding(keyPath)
        return ColorPicker(selection: color, supportsOpacity: false) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.wrappedValue)
                    .frame(width: 26, height: 26)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    }
                Text(AppStrings.text(title))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(EditorTheme.text)
                Spacer(minLength: 0)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private func occlusionControls(for layer: CoverTextLayer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("ui.cover.depth", symbol: "person.crop.rectangle")
            HStack(spacing: 0) {
                depthButton("ui.cover.front", depth: .front)
                depthButton("ui.cover.behindAll", depth: .behindAllPeople)
                depthButton("ui.cover.behindSelected", depth: .behindSelectedPeople)
            }
            .padding(3)
            .background(
                EditorTheme.surface,
                in: RoundedRectangle(cornerRadius: 10)
            )
            if layer.depth != .front {
                HStack {
                    Text(AppStrings.text("ui.cover.occlusionStrength"))
                    Spacer(minLength: 4)
                    Text("\(Int((layer.occlusionStrength * 100).rounded()))%")
                        .monospacedDigit()
                }
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.muted)
                Slider(value: layerBinding(\.occlusionStrength), in: 0...1)
                    .accessibilityLabel(AppStrings.text("ui.cover.occlusionStrength"))
            }
            if layer.depth == .behindSelectedPeople {
                Button {
                    isPickingPeople.toggle()
                } label: {
                    Label(
                        AppStrings.text(
                            isPickingPeople
                                ? "ui.cover.finishSelecting" : "ui.cover.selectPeople"
                        ),
                        systemImage: isPickingPeople ? "checkmark" : "cursorarrow.rays"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CoverEditorButtonStyle(
                    tone: isPickingPeople ? .primary : .secondary
                ))
                .disabled(people.isEmpty)
                Text(AppStrings.format(
                    "ui.cover.selectedCount",
                    layer.selectedPeople.count
                ))
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.muted)
            }
        }
    }

    private func depthButton(_ title: String, depth: CoverTextDepth) -> some View {
        let isSelected = selectedLayer?.depth == depth
        return Button {
            updateSelectedLayer { $0.depth = depth }
            isPickingPeople = false
        } label: {
            Text(AppStrings.text(title))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? EditorTheme.text : EditorTheme.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(EditorChoiceTabButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func sectionHeading(_ title: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EditorTheme.accent)
                .frame(width: 17)
            Text(AppStrings.text(title))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EditorTheme.text)
        }
    }

    private func labeledControl<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(AppStrings.text(title))
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.muted)
            content()
        }
    }

    @ViewBuilder
    private func personSelectionOverlay(size: CGSize) -> some View {
        if isPickingPeople {
            ZStack(alignment: .topLeading) {
                ForEach(people) { person in
                    let selected = selectedLayer?.selectedPeople.contains {
                        peopleAnalysis?.id(at: $0) == person.id
                    } ?? false
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            selected ? Color.yellow : Color.white.opacity(0.75),
                            style: StrokeStyle(lineWidth: selected ? 2.5 : 1, dash: [5, 4])
                        )
                        .frame(
                            width: person.bounds.width * size.width,
                            height: person.bounds.height * size.height
                        )
                        .position(
                            x: person.center.x * size.width,
                            y: person.center.y * size.height
                        )
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? .yellow : .white)
                        .shadow(color: .black, radius: 2)
                        .position(
                            x: person.bounds.minX * size.width + 8,
                            y: person.bounds.minY * size.height + 8
                        )
                }
                Text(AppStrings.text("ui.cover.pickHint"))
                    .font(.caption.weight(.semibold))
                    .padding(8)
                    .background(.black.opacity(0.68), in: Capsule())
                    .foregroundStyle(.white)
                    .frame(maxWidth: size.width, alignment: .center)
                    .padding(.top, 10)
            }
            .allowsHitTesting(false)
        }
    }

    private func slider(
        title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AppStrings.text(title))
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.muted)
            Slider(value: value, in: range)
                .tint(EditorTheme.accent)
        }
    }

    private func layerBinding<Value>(
        _ keyPath: WritableKeyPath<CoverTextLayer, Value>
    ) -> Binding<Value> {
        Binding(
            get: { selectedLayer![keyPath: keyPath] },
            set: { newValue in
                updateSelectedLayer { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func colorBinding(
        _ keyPath: WritableKeyPath<CoverTextLayer, String>
    ) -> Binding<Color> {
        Binding(
            get: {
                let hex = selectedLayer?[keyPath: keyPath] ?? "#FFFFFF"
                let value = UInt64(hex.dropFirst(), radix: 16) ?? 0xFFFFFF
                return Color(
                    .sRGB,
                    red: Double((value >> 16) & 0xFF) / 255,
                    green: Double((value >> 8) & 0xFF) / 255,
                    blue: Double(value & 0xFF) / 255
                )
            },
            set: { color in
                let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
                let hex = String(
                    format: "#%02X%02X%02X",
                    Int((ns.redComponent * 255).rounded()),
                    Int((ns.greenComponent * 255).rounded()),
                    Int((ns.blueComponent * 255).rounded())
                )
                updateSelectedLayer { $0[keyPath: keyPath] = hex }
            }
        )
    }

    private func loadInitialCover() {
        let existing = appModel.cover(for: videoID)
        if var existing {
            let position = currentVideoFrameTime()
            if let position,
               case let .videoFrame(frame)? = frameSource(at: position),
               existing.refreshVideoFrame(frame) {
                cover = existing
                persist()
            } else {
                cover = existing
            }
            selectedLayerID = existing.textLayers.first?.id
        } else {
            guard let position = currentVideoFrameTime() else { return }
            guard let source = frameSource(at: position) else { return }
            cover = VideoCover(source: source)
            persist()
        }
        loadImage()
    }

    private func chooseCurrentFrame() {
        guard let position = currentVideoFrameTime() else { return }
        guard let source = frameSource(at: position) else { return }
        cover?.source = source
        clearSelectedPeople()
        cover?.exportedImage = nil
        persist()
        loadImage()
    }

    private func currentVideoFrameTime() -> TimeInterval? {
        guard let video = appModel.selectedVideo, video.id == videoID else {
            return nil
        }
        // 打开时先锁定用户所选时间，避免播放器异步 seek 的定时回调覆盖它。
        return VideoFrameSnapshotter.captureTime(
            playerTime: nil,
            fallbackTime: appModel.coverEditorFrameTime ?? appModel.playbackTime,
            duration: video.metadata.durationSeconds,
            frameRate: video.metadata.frameRate
        )
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cover?.source = .image(appModel.coverResource(at: url))
        clearSelectedPeople()
        cover?.exportedImage = nil
        persist()
        loadImage()
    }

    private func addText() {
        let new = CoverTextLayer(
            text: AppStrings.text("ui.cover.defaultText")
        )
        cover?.textLayers.append(new)
        cover?.exportedImage = nil
        selectedLayerID = new.id
        persist()
        revision += 1
    }

    private func duplicateTextLayer(id: UUID) {
        guard let duplicate = cover?.duplicateTextLayer(id: id) else { return }
        liveLayer = nil
        canvasGesture = CanvasGestureState()
        selectedLayerID = duplicate.id
        isPickingPeople = false
        persist()
        revision += 1
    }

    private func removeSelectedLayer() {
        cover?.textLayers.removeAll { $0.id == selectedLayerID }
        cover?.exportedImage = nil
        selectedLayerID = cover?.textLayers.first?.id
        isPickingPeople = false
        persist()
        revision += 1
    }

    private func updateSelectedLayer(
        _ update: (inout CoverTextLayer) -> Void
    ) {
        guard let index = cover?.textLayers.firstIndex(where: {
            $0.id == selectedLayerID
        }) else { return }
        update(&cover!.textLayers[index])
        cover?.exportedImage = nil
        persist()
        revision += 1
    }

    private func persist() {
        guard let cover else { return }
        appModel.updateCover(cover, for: videoID)
    }

    private func clearSelectedPeople() {
        guard cover != nil else { return }
        for index in cover!.textLayers.indices {
            cover!.textLayers[index].selectedPeople = []
        }
        isPickingPeople = false
    }

    private func loadImage() {
        guard let cover else { return }
        imageLoadVersion += 1
        let loadVersion = imageLoadVersion
        isLoading = true
        message = nil
        revision += 1
        baseImage = nil
        previewBase = nil
        renderedImage = nil
        stationaryImage = nil
        followingImage = nil
        selectedTextImage = nil
        visibleTextMask = nil
        cachedLayer = nil
        liveLayer = nil
        peopleAnalysis = nil
        let request = appModel.coverRequest(for: videoID)
        let source = cover.source
        let sourceURL: URL?
        switch source {
        case .videoFrame:
            sourceURL = request?.inputURL
        case let .image(resource):
            sourceURL = appModel.resolveCoverResource(resource)
        }
        guard let sourceURL else {
            message = AppStrings.text("ui.cover.sourceMissing")
            isLoading = false
            return
        }
        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        Task {
            defer {
                if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() }
                if loadVersion == imageLoadVersion {
                    isLoading = false
                    if baseImage != nil { revision += 1 }
                }
            }
            do {
                let loaded: CGImage
                switch source {
                case let .videoFrame(frame):
                    guard var request else {
                        message = AppStrings.text("ui.cover.sourceMissing")
                        return
                    }
                    request.settings.aspectRatio = frame.aspectRatio
                    request.settings.maximumHeight = frame.maximumHeight
                    request.rotation = frame.rotation
                    loaded = try await Task.detached(priority: .userInitiated) {
                        try VideoFrameSnapshotter().renderImage(
                            request,
                            at: frame.seconds,
                            includeDataLayer: frame.includesDataLayer
                        )
                    }.value
                case .image:
                    let imageSource = try coverImageSource(url: sourceURL)
                    loaded = imageSource
                }
                guard loadVersion == imageLoadVersion, cover.source == self.cover?.source else {
                    return
                }
                let preview = downscale(loaded)
                baseImage = loaded
                previewBase = preview
                renderedImage = preview
                do {
                    let detected = try await Task.detached(priority: .userInitiated) {
                        try CoverPeopleAnalysis(image: preview)
                    }.value
                    guard loadVersion == imageLoadVersion else { return }
                    peopleAnalysis = detected
                } catch {
                    if loadVersion == imageLoadVersion {
                        message = error.localizedDescription
                    }
                }
            } catch {
                if loadVersion == imageLoadVersion { message = error.localizedDescription }
            }
        }
    }

    /// 静态内容在后台合成一次；拖拽期间只变换独立的文字图层。
    private func startRenderLoop() {
        guard renderLoop == nil else { return }
        renderLoop = Task {
            while !Task.isCancelled {
                if !isLoading,
                   renderedRevision != revision,
                   let preview = previewBase,
                   let cover {
                    let requestedRevision = revision
                    renderedRevision = requestedRevision
                    let layers = cover.textLayers
                    let activeID = selectedLayerID
                    let analysis = peopleAnalysis
                    let result = try? await Task.detached(priority: .userInitiated) {
                        let composer = CoverComposer()
                        let composed = try composer.render(
                            image: preview,
                            layers: layers,
                            people: analysis
                        )
                        guard let selectedIndex = layers.firstIndex(where: {
                            $0.id == activeID
                        }) else {
                            return CoverPreviewLayers(composed: composed)
                        }
                        let selected = layers[selectedIndex]
                        guard
                              !selected.text.isEmpty else {
                            return CoverPreviewLayers(composed: composed)
                        }
                        let stationary = try composer.render(
                            image: preview,
                            layers: Array(layers[..<selectedIndex]),
                            people: analysis
                        )
                        let following = try composer.renderLayerOverlay(
                            imageSize: CGSize(width: preview.width, height: preview.height),
                            layers: Array(layers[(selectedIndex + 1)...]),
                            people: analysis
                        )
                        let text = try composer.renderTextOverlay(
                            imageSize: CGSize(width: preview.width, height: preview.height),
                            layer: selected
                        )
                        let mask = try composer.visibleTextMask(
                            imageSize: CGSize(width: preview.width, height: preview.height),
                            layer: selected,
                            people: analysis
                        )
                        return CoverPreviewLayers(
                            composed: composed,
                            stationary: stationary,
                            following: following,
                            selectedText: text,
                            visibleMask: mask,
                            selectedLayer: selected
                        )
                    }.value
                    guard !Task.isCancelled else { return }
                    if requestedRevision == revision, let result {
                        renderedImage = result.composed
                        stationaryImage = result.stationary
                        followingImage = result.following
                        selectedTextImage = result.selectedText
                        visibleTextMask = result.visibleMask
                        cachedLayer = result.selectedLayer
                        if canvasGesture.mode == .inactive,
                           liveLayer?.id == result.selectedLayer?.id,
                           cover.textLayers.first(where: {
                               $0.id == liveLayer?.id
                           }) == liveLayer {
                            liveLayer = nil
                        }
                        message = nil
                    }
                } else {
                    try? await Task.sleep(for: .milliseconds(8))
                }
            }
        }
    }

    private func exportCover() {
        guard let baseImage, let cover else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "RunOverlay-Cover.png"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        let accessed = outputURL.deletingLastPathComponent()
            .startAccessingSecurityScopedResource()
        defer {
            if accessed {
                outputURL.deletingLastPathComponent()
                    .stopAccessingSecurityScopedResource()
            }
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            message = AppStrings.text("ui.cover.outputExists")
            return
        }
        let layers = cover.textLayers
        isExportingCover = true
        Task {
            defer { isExportingCover = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let image = try CoverComposer().render(
                        image: baseImage,
                        layers: layers
                    )
                    guard let data = CoverImageEncoding.encode(
                        image,
                        as: outputURL.pathExtension
                    ) else {
                        throw VideoFrameSnapshotError.imageCreationFailed
                    }
                    return data
                }.value
                try data.write(to: outputURL, options: .withoutOverwriting)
                self.cover?.exportedImage = appModel.coverResource(at: outputURL)
                persist()
                message = AppStrings.text("ui.cover.exported")
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func downscale(_ image: CGImage, maxDimension: CGFloat = 1_280) -> CGImage {
        let longEdge = CGFloat(max(image.width, image.height))
        guard longEdge > maxDimension else { return image }
        let scale = maxDimension / CGFloat(longEdge)
        let width = max(2, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(2, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    @ViewBuilder
    private func selectionFrameOverlay(size: CGSize) -> some View {
        if !isPickingPeople, let layer = selectedLayer {
            let rect = frameRect(of: layer, size: size)
            if rect.width > 0 {
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .frame(width: rect.width, height: rect.height)
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            EditorTheme.accent,
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                        .frame(width: rect.width, height: rect.height)
                    ForEach(CoverFrameCorner.allCases, id: \.self) { corner in
                        Circle()
                            .fill(EditorTheme.accent)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                            .frame(width: 9, height: 9)
                            .position(localHandlePoint(corner, in: rect))
                    }
                    Rectangle()
                        .fill(EditorTheme.accent.opacity(0.75))
                        .frame(width: 1, height: 22)
                        .position(x: rect.width / 2, y: -17)
                    Circle()
                        .fill(EditorTheme.canvas)
                        .frame(width: 17, height: 17)
                        .overlay {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(EditorTheme.accent)
                        }
                        .overlay(Circle().strokeBorder(EditorTheme.accent, lineWidth: 1.5))
                        .position(x: rect.width / 2, y: -32)
                }
                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                .rotationEffect(.degrees(layer.rotationDegrees))
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
            }
        }
    }

    private func frameRect(of layer: CoverTextLayer, size: CGSize) -> CGRect {
        let frame = CoverComposer().textFrame(of: layer, imageSize: size)
        guard frame.width > 0, frame.height > 0 else { return .zero }
        let pad: CGFloat = 6
        return CGRect(
            x: frame.minX * size.width - pad,
            y: frame.minY * size.height - pad,
            width: frame.width * size.width + pad * 2,
            height: frame.height * size.height + pad * 2
        )
    }

    @ViewBuilder
    private func centerAlignmentGuides(size: CGSize) -> some View {
        if centerSnapGuides.horizontal || centerSnapGuides.vertical {
            Path { path in
                if centerSnapGuides.horizontal {
                    path.move(to: CGPoint(x: size.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                }
                if centerSnapGuides.vertical {
                    path.move(to: CGPoint(x: 0, y: size.height / 2))
                    path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                }
            }
            .stroke(
                EditorTheme.accent.opacity(0.9),
                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
            )
            .allowsHitTesting(false)
        }
    }

    private func handlePoint(
        _ corner: CoverFrameCorner,
        in rect: CGRect
    ) -> CGPoint {
        switch corner {
        case .topLeading: CGPoint(x: rect.minX, y: rect.minY)
        case .topTrailing: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeading: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomTrailing: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func localHandlePoint(_ corner: CoverFrameCorner, in rect: CGRect) -> CGPoint {
        let point = handlePoint(corner, in: rect)
        return CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
    }

    private func opposite(_ corner: CoverFrameCorner) -> CoverFrameCorner {
        switch corner {
        case .topLeading: .bottomTrailing
        case .topTrailing: .bottomLeading
        case .bottomLeading: .topTrailing
        case .bottomTrailing: .topLeading
        }
    }

    private func corner(
        at point: CGPoint,
        in rect: CGRect,
        rotation: Double
    ) -> CoverFrameCorner? {
        CoverFrameCorner.allCases.first { corner in
            let handle = CoverCanvasGeometry.rotate(
                handlePoint(corner, in: rect),
                around: CGPoint(x: rect.midX, y: rect.midY),
                degrees: rotation
            )
            return hypot(point.x - handle.x, point.y - handle.y) <= 11
        }
    }

    private func index(of layerID: UUID) -> Int? {
        cover?.textLayers.firstIndex(where: { $0.id == layerID })
    }

    private func clearSelectedLayer() {
        guard selectedLayerID != nil else { return }
        liveLayer = nil
        selectedLayerID = nil
        isPickingPeople = false
        canvasGesture = CanvasGestureState()
        centerSnapGuides = (false, false)
        setHoverCursor(nil)
    }

    private func beginCanvasGesture(at point: CGPoint, size: CGSize) {
        centerSnapGuides = (false, false)
        guard let cover else {
            canvasGesture = CanvasGestureState()
            return
        }
        if cachedLayer?.id == selectedLayerID,
           stationaryImage != nil,
           selectedTextImage != nil,
           let layer = selectedLayer {
            let rect = frameRect(of: layer, size: size)
            if rect.width > 0 {
                let rotateHandle = CoverCanvasGeometry.rotationHandle(
                    for: rect,
                    degrees: layer.rotationDegrees
                )
                if hypot(point.x - rotateHandle.x, point.y - rotateHandle.y) <= 14 {
                    liveLayer = layer
                    canvasGesture = CanvasGestureState(
                        mode: .rotate(layer.id),
                        startRotation: layer.rotationDegrees,
                        startRect: rect
                    )
                    return
                }
                if let corner = corner(
                    at: point,
                    in: rect,
                    rotation: layer.rotationDegrees
                ) {
                    liveLayer = layer
                    canvasGesture = CanvasGestureState(
                        mode: .resize(layer.id, corner),
                        startFontHeight: layer.fontHeight,
                        startRect: rect,
                        startVerticalOffset: rect.midY / max(size.height, 1) -
                            layer.position.y
                    )
                    return
                }
                if rect.contains(CoverCanvasGeometry.localPoint(
                    point,
                    rect: rect,
                    degrees: layer.rotationDegrees
                )) {
                    liveLayer = layer
                    canvasGesture = CanvasGestureState(
                        mode: .move(layer.id),
                        startPosition: layer.position,
                        startRect: rect
                    )
                    return
                }
            }
        }
        if let hitID = CoverTextHitTester().layerID(
            at: point,
            in: size,
            layers: cover.textLayers
        ) {
            if selectedLayerID != hitID {
                liveLayer = nil
                selectedLayerID = hitID
                canvasGesture = CanvasGestureState()
            }
            return
        }
        canvasGesture = CanvasGestureState()
    }

    private func handleCanvasChange(
        _ value: DragGesture.Value,
        size: CGSize
    ) {
        guard !isPickingPeople, baseImage != nil else { return }
        if canvasGesture.mode == .inactive {
            beginCanvasGesture(at: value.startLocation, size: size)
        }
        switch canvasGesture.mode {
        case .move(let id):
            guard let start = canvasGesture.startPosition,
                  liveLayer?.id == id,
                  hypot(value.translation.width, value.translation.height) > 2
            else { return }
            let snap = CoverTextCenterSnap.resolve(
                from: start,
                frame: canvasGesture.startRect,
                translation: value.translation,
                canvasSize: size
            )
            if centerSnapGuides.horizontal != snap.horizontal ||
                centerSnapGuides.vertical != snap.vertical {
                centerSnapGuides = (snap.horizontal, snap.vertical)
            }
            guard liveLayer?.position != snap.position else { return }
            liveLayer?.position = snap.position
        case .resize(let id, let corner):
            guard liveLayer?.id == id,
                  canvasGesture.startRect.width > 0,
                  canvasGesture.startFontHeight > 0 else { return }
            let startRect = canvasGesture.startRect
            let localLocation = CoverCanvasGeometry.localPoint(
                value.location,
                rect: startRect,
                degrees: liveLayer?.rotationDegrees ?? 0
            )
            let anchor = handlePoint(opposite(corner), in: startRect)
            let start = handlePoint(corner, in: startRect)
            let initial = hypot(start.x - anchor.x, start.y - anchor.y)
            guard initial > 8 else { return }
            let current = hypot(localLocation.x - anchor.x, localLocation.y - anchor.y)
            let scale = max(current / initial, 0.05)
            let fontHeight = min(
                max(
                    canvasGesture.startFontHeight * scale,
                    CoverTextLayer.fontHeightRange.lowerBound
                ),
                CoverTextLayer.fontHeightRange.upperBound
            )
            let ratio = fontHeight / canvasGesture.startFontHeight
            let localCenter = CGPoint(
                x: anchor.x + (startRect.midX - anchor.x) * ratio,
                y: anchor.y + (startRect.midY - anchor.y) * ratio
            )
            let center = CoverCanvasGeometry.rotate(
                localCenter,
                around: CGPoint(x: startRect.midX, y: startRect.midY),
                degrees: liveLayer?.rotationDegrees ?? 0
            )
            liveLayer?.fontHeight = fontHeight
            liveLayer?.position = CoverPoint(
                x: min(max(center.x / max(size.width, 1), 0), 1),
                y: min(max(
                    center.y / max(size.height, 1) -
                        canvasGesture.startVerticalOffset * ratio,
                    0), 1)
            )
        case .rotate(let id):
            guard liveLayer?.id == id else { return }
            liveLayer?.rotationDegrees = CoverCanvasGeometry.updatedRotation(
                from: canvasGesture.startRotation,
                initial: value.startLocation,
                current: value.location,
                center: CGPoint(
                    x: canvasGesture.startRect.midX,
                    y: canvasGesture.startRect.midY
                )
            )
        case .inactive:
            break
        }
    }

    private func handleCanvasEnd(
        _ value: DragGesture.Value,
        size: CGSize
    ) {
        centerSnapGuides = (false, false)
        if isPickingPeople {
            pickPerson(at: value.location, size: size)
            canvasGesture = CanvasGestureState()
            return
        }
        switch canvasGesture.mode {
        case .inactive:
            guard hypot(value.translation.width, value.translation.height) <= 3,
                  let cover,
                  CoverTextHitTester().layerID(
                    at: value.startLocation,
                    in: size,
                    layers: cover.textLayers
                  ) == nil else { break }
            clearSelectedLayer()
        case .move, .resize, .rotate:
            commitLiveLayer()
        }
        canvasGesture = CanvasGestureState()
        setHoverCursor(nil)
    }

    /// 松手时把拖动结果一次性写回模型：只产生一次撤销记录和一次自动保存。
    private func commitLiveLayer() {
        guard let live = liveLayer else { return }
        guard let index = cover?.textLayers.firstIndex(where: {
            $0.id == live.id
        }) else {
            liveLayer = nil
            return
        }
        guard cover?.textLayers[index] != live else {
            liveLayer = nil
            return
        }
        cover?.textLayers[index] = live
        cover?.exportedImage = nil
        persist()
        revision += 1
    }

    private func pickPerson(at location: CGPoint, size: CGSize) {
        guard baseImage != nil else { return }
        let point = CoverPoint(
            x: min(max(location.x / max(size.width, 1), 0), 1),
            y: min(max(location.y / max(size.height, 1), 0), 1)
        )
        guard let analysis = peopleAnalysis,
              let tappedID = analysis.id(at: point) else {
            message = AppStrings.text("ui.cover.notPerson")
            return
        }
        let alreadySelected = selectedLayer?.selectedPeople.firstIndex(where: {
            analysis.id(at: $0) == tappedID
        })
        updateSelectedLayer { layer in
            if let index = alreadySelected {
                layer.selectedPeople.remove(at: index)
            } else {
                layer.selectedPeople.append(point)
            }
        }
        message = nil
    }

    private func updateHoverCursor(at point: CGPoint, size: CGSize) {
        let cursor: NSCursor?
        if !isPickingPeople, let layer = selectedLayer {
            let rect = frameRect(of: layer, size: size)
            let rotateHandle = CoverCanvasGeometry.rotationHandle(
                for: rect,
                degrees: layer.rotationDegrees
            )
            if rect.width > 0,
               hypot(point.x - rotateHandle.x, point.y - rotateHandle.y) <= 14 {
                cursor = .crosshair
            } else if rect.width > 0, let corner = corner(
                at: point,
                in: rect,
                rotation: layer.rotationDegrees
            ) {
                cursor = Self.diagonalCursor(for: corner)
            } else if rect.width > 0,
                      rect.contains(CoverCanvasGeometry.localPoint(
                          point,
                          rect: rect,
                          degrees: layer.rotationDegrees
                      )) {
                cursor = .openHand
            } else {
                cursor = nil
            }
        } else {
            cursor = nil
        }
        setHoverCursor(cursor)
    }

    private func setHoverCursor(_ cursor: NSCursor?) {
        guard hoveredCursor !== cursor else { return }
        hoveredCursor?.pop()
        cursor?.push()
        hoveredCursor = cursor
    }

    /// 光标实例全局缓存：悬停时反复新建光标并 push/pop 会造成明显卡顿。
    private static let resizeCursors: [CoverFrameCorner: NSCursor] = {
        let mainDiagonal = diagonalCursorImage(
            symbol: "arrow.up.left.and.arrow.down.right"
        )
        let antiDiagonal = diagonalCursorImage(
            symbol: "arrow.up.right.and.arrow.down.left"
        )
        return [
            .topLeading: mainDiagonal,
            .bottomTrailing: mainDiagonal,
            .topTrailing: antiDiagonal,
            .bottomLeading: antiDiagonal
        ]
    }()

    private static func diagonalCursor(for corner: CoverFrameCorner) -> NSCursor {
        resizeCursors[corner] ?? .arrow
    }

    private static func diagonalCursorImage(symbol: String) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }

    private func fittedSize(source: CGSize, available: CGSize) -> CGSize {
        let scale = min(
            available.width / max(source.width, 1),
            available.height / max(source.height, 1)
        )
        return CGSize(width: source.width * scale, height: source.height * scale)
    }

    private func coverImageSource(url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4_096
                ] as CFDictionary
              ) else {
            throw VideoFrameSnapshotError.imageCreationFailed
        }
        return image
    }
}

private enum CoverFontFilter {
    case chinese
    case all
}

private enum CoverFrameCorner: CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

private enum CoverCanvasGeometry {
    static func rotate(_ point: CGPoint, around center: CGPoint, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        let dx = point.x - center.x
        let dy = point.y - center.y
        return CGPoint(
            x: center.x + dx * cos(radians) - dy * sin(radians),
            y: center.y + dx * sin(radians) + dy * cos(radians)
        )
    }

    static func localPoint(_ point: CGPoint, rect: CGRect, degrees: Double) -> CGPoint {
        rotate(point, around: CGPoint(x: rect.midX, y: rect.midY), degrees: -degrees)
    }

    static func rotationHandle(for rect: CGRect, degrees: Double) -> CGPoint {
        rotate(
            CGPoint(x: rect.midX, y: rect.minY - 32),
            around: CGPoint(x: rect.midX, y: rect.midY),
            degrees: degrees
        )
    }

    static func updatedRotation(
        from start: Double,
        initial: CGPoint,
        current: CGPoint,
        center: CGPoint
    ) -> Double {
        let old = atan2(initial.y - center.y, initial.x - center.x)
        let new = atan2(current.y - center.y, current.x - center.x)
        let delta = (new - old) * 180 / .pi
        return (start + delta + 540).truncatingRemainder(dividingBy: 360) - 180
    }
}

private struct CanvasGestureState: Equatable {
    var mode: Mode = .inactive
    var startPosition: CoverPoint?
    var startFontHeight: Double = 0
    var startRotation: Double = 0
    var startRect: CGRect = .zero
    var startVerticalOffset: Double = 0

    enum Mode: Equatable {
        case inactive
        case move(UUID)
        case resize(UUID, CoverFrameCorner)
        case rotate(UUID)
    }
}

private struct CoverPreviewLayers {
    let composed: CGImage
    let stationary: CGImage?
    let following: CGImage?
    let selectedText: CGImage?
    let visibleMask: CGImage?
    let selectedLayer: CoverTextLayer?

    init(
        composed: CGImage,
        stationary: CGImage? = nil,
        following: CGImage? = nil,
        selectedText: CGImage? = nil,
        visibleMask: CGImage? = nil,
        selectedLayer: CoverTextLayer? = nil
    ) {
        self.composed = composed
        self.stationary = stationary
        self.following = following
        self.selectedText = selectedText
        self.visibleMask = visibleMask
        self.selectedLayer = selectedLayer
    }
}

private struct CoverEditorButtonStyle: ButtonStyle {
    enum Tone {
        case primary
        case secondary
        case layer
        case font
        case palette
        case destructive
}

    @Environment(\.isEnabled) private var isEnabled
    let tone: Tone
    var isSelected = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let isPill = tone == .primary || tone == .secondary ||
            tone == .destructive
        let buttonHeight: CGFloat = tone == .layer || tone == .palette
            ? 54 : (isPill ? 52 : 46)
        let buttonShape = RoundedRectangle(
            cornerRadius: isPill ? buttonHeight / 2 : 10
        )
        let background: Color = switch tone {
        case .primary:
            isHovered ? EditorTheme.accent.opacity(0.88) : EditorTheme.accent
        case .secondary:
            isHovered ? EditorTheme.accent.opacity(0.1) : EditorTheme.sidebar
        case .layer:
            isSelected ? EditorTheme.raised
                : (isHovered ? EditorTheme.surface : EditorTheme.surface.opacity(0.55))
        case .font, .palette:
            isSelected ? EditorTheme.raised
                : (isHovered ? EditorTheme.raised.opacity(0.78) : EditorTheme.surface)
        case .destructive:
            isHovered ? Color.red.opacity(0.14) : EditorTheme.sidebar
        }
        let foreground: Color = switch tone {
        case .primary: EditorTheme.canvas
        case .secondary: EditorTheme.accent
        case .destructive: isHovered ? Color.red : EditorTheme.muted
        default: isSelected ? EditorTheme.accent : EditorTheme.text
        }
        configuration.label
            .font(.system(
                size: isPill ? 14 : 13,
                weight: isSelected || tone == .primary ? .semibold : .medium
            ))
            .foregroundStyle(isEnabled ? foreground : EditorTheme.muted)
            .padding(.horizontal, tone == .palette ? 0 : (isPill ? 23 : 14))
            .frame(minHeight: buttonHeight)
            .background(
                isEnabled ? background : EditorTheme.surface.opacity(0.5),
                in: buttonShape
            )
            .overlay {
                buttonShape
                    .strokeBorder(
                        !isEnabled ? .clear
                            : tone == .secondary ? EditorTheme.accent
                            : tone == .destructive ? EditorTheme.muted.opacity(0.4)
                            : isSelected ? EditorTheme.accent.opacity(0.45)
                            : .clear,
                        lineWidth: tone == .secondary ? 1.5 : 1
                    )
            }
            .contentShape(buttonShape)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.16), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension Color {
    init(coverHex hex: String) {
        let normalized = hex.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted
        )
        let value = UInt64(normalized, radix: 16) ?? 0xFFFFFF
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
