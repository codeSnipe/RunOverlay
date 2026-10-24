import RunOverlayCore
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isShowingRouteCalibration = false
    @State private var isShowingSaveDraft = false
    @State private var draftName = ""
    @State private var makeDraftDefault = true
    @State private var draftPendingDeletion: OverlayDraft?
    @State private var editingElementID: UUID?
    @State private var isShowingRecommendedColors = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EditorTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.text("ui.inspector.title"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(EditorTheme.text)
                    Text(appModel.editingOverlayConfiguration.preset.displayName)
                        .font(.caption)
                        .foregroundStyle(EditorTheme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle()
                .fill(EditorTheme.separator)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
            InspectorSection(
                title: AppStrings.text("ui.overlay.templateSection"),
                symbol: "square.stack.3d.up"
            ) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(AppStrings.text("ui.overlay.applyTo"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EditorTheme.muted)

                    HStack(spacing: 0) {
                        ForEach(OverlayEditingScope.allCases, id: \.self) { scope in
                            let isSelected = appModel.overlayEditingScope == scope
                            Button {
                                appModel.setOverlayEditingScope(scope)
                            } label: {
                                Text(scope.displayName)
                                    .font(.system(
                                        size: 12,
                                        weight: isSelected ? .semibold : .medium
                                    ))
                                    .foregroundStyle(
                                        isSelected ? EditorTheme.text : EditorTheme.muted
                                    )
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(EditorChoiceTabButtonStyle(isSelected: isSelected))
                            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        }
                    }
                    .padding(3)
                    .background(
                        EditorTheme.surface,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .disabled(appModel.selectedVideo == nil)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.text("ui.overlay.style"))
                        .foregroundStyle(EditorTheme.muted)
                    EditorChoiceTabs(
                        options: OverlayTemplatePreset.allCases,
                        selection: appModel.editingOverlayConfiguration.preset,
                        columns: 3,
                        title: { $0.displayName },
                        onSelect: { appModel.setTemplate($0) }
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.text("ui.overlay.accentColor"))
                        .foregroundStyle(EditorTheme.muted)
                    accentColorControls
                }

                if appModel.overlayEditingScope == .currentVideo {
                    Button(AppStrings.text("ui.overlay.restoreProject")) {
                        appModel.resetCurrentVideoOverlay()
                    }
                    .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                    .disabled(appModel.selectedVideo?.overlayOverride == nil)
                }
            }

            InspectorSection(
                title: AppStrings.text("ui.draft.section"),
                symbol: "square.on.square"
            ) {
                Button {
                    draftName = ""
                    makeDraftDefault = true
                    isShowingSaveDraft = true
                } label: {
                    Label(
                        AppStrings.text("ui.draft.saveCurrent"),
                        systemImage: "square.and.arrow.down"
                    )
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))

                Button {
                    appModel.presentImportOverlayDraftPanel()
                } label: {
                    Label(
                        AppStrings.text("ui.draft.import"),
                        systemImage: "square.and.arrow.down.on.square"
                    )
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))

                if appModel.overlayDraftLibrary.drafts.isEmpty {
                    Text(AppStrings.text("ui.draft.empty"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                } else {
                    Rectangle()
                        .fill(EditorTheme.separator)
                        .frame(height: 1)
                        .padding(.top, 4)

                    ForEach(appModel.overlayDraftLibrary.drafts) { draft in
                        HStack(spacing: 8) {
                            Button {
                                appModel.applyOverlayDraft(draft.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(draft.name)
                                        .lineLimit(1)
                                    Text(draft.configuration.preset.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(EditorActionButtonStyle(tone: .quiet, size: .compact))
                            .help(AppStrings.text("ui.draft.apply"))

                            Button {
                                appModel.setDefaultOverlayDraft(draft.id)
                            } label: {
                                Image(
                                    systemName: appModel.overlayDraftLibrary.defaultDraftID ==
                                        draft.id ? "star.fill" : "star"
                                )
                                .foregroundStyle(
                                    appModel.overlayDraftLibrary.defaultDraftID == draft.id
                                        ? EditorTheme.accent
                                        : Color.secondary
                                )
                            }
                            .buttonStyle(EditorActionButtonStyle(tone: .quiet, size: .smallIcon))
                            .help(
                                AppStrings.text(
                                    appModel.overlayDraftLibrary.defaultDraftID == draft.id
                                        ? "ui.draft.isDefault"
                                        : "ui.draft.setDefault"
                                )
                            )
                            .accessibilityLabel(
                                AppStrings.text(
                                    appModel.overlayDraftLibrary.defaultDraftID == draft.id
                                        ? "ui.draft.isDefault"
                                        : "ui.draft.setDefault"
                                )
                            )
                            .disabled(appModel.overlayDraftLibrary.defaultDraftID == draft.id)

                            Button {
                                appModel.presentExportOverlayDraftPanel(draft.id)
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(EditorActionButtonStyle(tone: .quiet, size: .smallIcon))
                            .help(AppStrings.text("ui.draft.export"))
                            .accessibilityLabel(AppStrings.text("ui.draft.export"))

                            Button {
                                draftPendingDeletion = draft
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(EditorActionButtonStyle(tone: .destructive, size: .smallIcon))
                            .help(AppStrings.text("ui.draft.delete"))
                            .accessibilityLabel(AppStrings.text("ui.draft.delete"))
                        }
                        .padding(.vertical, 7)
                    }
                }
            }

            InspectorSection(
                title: AppStrings.text("ui.overlay.elements"),
                symbol: "square.grid.2x2"
            ) {
                Text(AppStrings.text("ui.overlay.editHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6)
                    ],
                    spacing: 6
                ) {
                    ForEach(OverlayElementKind.cardOrder, id: \.self) { kind in
                        let element = appModel.editingOverlayConfiguration.elements
                            .first { $0.kind == kind }
                        OverlayLayerCard(
                            kind: kind,
                            isVisible: element?.isVisible ?? false,
                            isEditing: editingElementID == element?.id,
                            onToggleVisibility: {
                                appModel.toggleOverlayElement(kind)
                            },
                            onEdit: {
                                let id = appModel.ensureOverlayElement(kind)
                                editingElementID = editingElementID == id ? nil : id
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity)

                if let editingElementID,
                   let element = appModel.editingOverlayConfiguration.elements.first(
                    where: { $0.id == editingElementID }
                   ) {
                    InspectorElementEditor(
                        element: element,
                        preset: appModel.editingOverlayConfiguration.preset,
                        onClose: { self.editingElementID = nil }
                    )
                    .environmentObject(appModel)
                }
            }

            if let video = appModel.selectedVideo {
                InspectorSection(
                    title: AppStrings.text("ui.video.sectionTitle"),
                    symbol: "film"
                ) {
                    LabeledContent(AppStrings.text("ui.video.file"), value: video.fileName)
                    LabeledContent(
                        AppStrings.text("ui.video.size"),
                        value: video.metadata.dimensions.displayText
                    )
                    LabeledContent(
                        AppStrings.text("ui.video.frameRate"),
                        value: AppStrings.format("ui.video.frameRateValue", video.metadata.frameRate)
                    )
                    LabeledContent(
                        AppStrings.text("ui.video.duration"),
                        value: RunOverlayFormatters.duration(
                            video.metadata.durationSeconds
                        )
                    )
                    LabeledContent(
                        AppStrings.text("ui.video.fileSize"),
                        value: RunOverlayFormatters.fileSize(
                            video.metadata.fileSizeBytes
                        )
                    )
                    LabeledContent(
                        AppStrings.text("ui.video.audio"),
                        value: AppStrings.text(
                            video.metadata.hasAudio ? "ui.video.audioRetained" : "ui.video.noAudio"
                        )
                    )
                    if let timeResource = video.timeResource {
                        LabeledContent(
                            AppStrings.text("ui.video.timeResourceLabel"),
                            value: timeResource.fileName
                        )
                        if appModel.missingVideoTimeResourceIDs.contains(video.id) {
                            LabeledContent(
                                AppStrings.text("ui.video.resourceStatus"),
                                value: AppStrings.text("ui.video.timeResourceMissing")
                            )
                                .foregroundStyle(.red)
                        }
                        LabeledContent(
                            AppStrings.text("ui.video.capturedAt"),
                            value: video.effectiveCapturedAt.map {
                                $0.formatted(date: .numeric, time: .standard)
                            } ?? AppStrings.text("ui.video.unresolved")
                        )
                    }
                }

                InspectorSection(
                    title: AppStrings.text("ui.match.section"),
                    symbol: "waveform.path.ecg"
                ) {
                    LabeledContent(
                        AppStrings.text("ui.match.status"),
                        value: video.activityMatch.status.displayName
                    )
                    LabeledContent(
                        AppStrings.text("ui.match.timeOffset"),
                        value: AppStrings.format(
                            "ui.match.timeOffsetValue",
                            video.activityMatch.timeOffset
                        )
                    )

                    HStack {
                        Text(AppStrings.text("ui.match.offsetSeconds"))
                        Spacer()
                        TextField(
                            "0",
                            value: Binding(
                                get: { video.activityMatch.timeOffset },
                                set: { appModel.setSelectedVideoTimeOffset($0) }
                            ),
                            format: .number.precision(.fractionLength(3))
                        )
                        .multilineTextAlignment(.trailing)
                        .frame(width: 92)
                    }

                    HStack {
                        Button(AppStrings.text("ui.match.minusSecond")) {
                            appModel.setSelectedVideoTimeOffset(
                                video.activityMatch.timeOffset - 1
                            )
                        }
                        .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                        Button(AppStrings.text("ui.match.plusSecond")) {
                            appModel.setSelectedVideoTimeOffset(
                                video.activityMatch.timeOffset + 1
                            )
                        }
                        .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                        Button(AppStrings.text("ui.common.reset")) {
                            appModel.setSelectedVideoTimeOffset(0)
                        }
                        .buttonStyle(EditorActionButtonStyle(tone: .quiet, size: .compact))
                    }
                    .disabled(appModel.project.activitySource == nil)

                    Button(AppStrings.text("ui.match.calibrate")) {
                        isShowingRouteCalibration = true
                    }
                    .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                    .disabled(
                        appModel.project.activitySamples
                            .filter { $0.coordinate != nil }
                            .isEmpty
                    )
                }
            } else {
                InspectorSection(
                    title: AppStrings.text("ui.video.sectionTitle"),
                    symbol: "film"
                ) {
                    Text(AppStrings.text("ui.video.selectHint"))
                        .foregroundStyle(.secondary)
                }
            }

            if let source = appModel.project.activitySource {
                InspectorSection(
                    title: AppStrings.text("ui.activity.sectionTitle"),
                    symbol: "figure.run"
                ) {
                    LabeledContent(
                        AppStrings.text("ui.activity.type"),
                        value: source.kind.rawValue.uppercased()
                    )
                    LabeledContent(
                        AppStrings.text("ui.activity.recordCount"),
                        value: "\(source.sampleCount)"
                    )

                    ForEach(
                        ActivityDataChannel.allCases.filter {
                            source.availableChannels.contains($0)
                        },
                        id: \.self
                    ) { channel in
                        Label(channel.displayName, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppStrings.text("ui.activity.smoothing"))
                            .foregroundStyle(EditorTheme.muted)
                        EditorChoiceTabs(
                            options: [SmoothingLevel.off, .light, .standard, .strong],
                            selection: appModel.project.smoothingLevel,
                            columns: 4,
                            title: { $0.displayName },
                            onSelect: { appModel.setSmoothingLevel($0) }
                        )
                    }
                }
            }

            InspectorSection(
                title: AppStrings.text("ui.export.presets"),
                symbol: "square.and.arrow.up"
            ) {
                LabeledContent(
                    AppStrings.text("ui.export.resolution"),
                    value: "\(appModel.project.exportSettings.maximumHeight)p"
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.text("ui.export.aspectRatio"))
                        .foregroundStyle(EditorTheme.muted)
                    EditorChoiceTabs(
                        options: ExportAspectRatio.allCases,
                        selection: appModel.project.exportSettings.aspectRatio,
                        columns: 3,
                        title: { $0.displayName },
                        onSelect: { appModel.setExportAspectRatio($0) }
                    )
                }
                LabeledContent(
                    AppStrings.text("ui.export.directory")
                ) {
                    Text(
                        appModel.exportDirectoryDisplayName ??
                            AppStrings.text("ui.export.notSet")
                    )
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.trailing)
                    .help(appModel.exportDirectoryDisplayName ?? "")
                }
                Button {
                    appModel.configureExportDirectory()
                } label: {
                    Label(AppStrings.text("ui.export.setDirectory"), systemImage: "folder")
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                .disabled(appModel.isExporting)

                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.text("ui.export.format"))
                        .foregroundStyle(EditorTheme.muted)
                    EditorChoiceTabs(
                        options: [ExportSettings.Codec.h264, .hevc],
                        selection: appModel.project.exportSettings.codec,
                        columns: 2,
                        title: { $0.displayName },
                        onSelect: { appModel.setExportCodec($0) }
                    )
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.text("ui.export.parallelTasks"))
                        .foregroundStyle(EditorTheme.muted)
                    EditorChoiceTabs(
                        options: [1, 2, 3],
                        selection: appModel.project.exportSettings.parallelTaskCount,
                        columns: 3,
                        title: {
                            $0 == 1 ? AppStrings.text("ui.export.oneRecommended") : "\($0)"
                        },
                        onSelect: { appModel.setExportParallelTaskCount($0) }
                    )
                }
                LabeledContent(
                    AppStrings.text("ui.video.audio"),
                    value: AppStrings.text("ui.video.audioRetained")
                )
            }
                }
                .padding(16)
            }
            .font(.system(size: 12))
            .controlSize(.small)
        }
        .background(EditorTheme.inspector)
        .onChange(of: appModel.overlayEditingScope) { _, _ in
            editingElementID = nil
        }
        .onChange(of: appModel.selectedVideoID) { _, _ in
            editingElementID = nil
        }
        .sheet(isPresented: $isShowingRouteCalibration) {
            RouteCalibrationView()
                .environmentObject(appModel)
        }
        .sheet(isPresented: $isShowingSaveDraft) {
            VStack(alignment: .leading, spacing: 16) {
                Text(AppStrings.text("ui.draft.saveTitle"))
                    .font(.title2.bold())
                Text(AppStrings.text("ui.draft.saveHint"))
                    .foregroundStyle(.secondary)
                TextField(AppStrings.text("ui.draft.name"), text: $draftName)
                    .textFieldStyle(.roundedBorder)
                Toggle(
                    AppStrings.text("ui.draft.makeDefault"),
                    isOn: $makeDraftDefault
                )
                HStack {
                    Spacer()
                    Button(AppStrings.text("ui.common.cancel")) {
                        isShowingSaveDraft = false
                    }
                    .buttonStyle(EditorActionButtonStyle(tone: .outline))
                    Button(AppStrings.text("ui.draft.save")) {
                        appModel.saveOverlayDraft(
                            named: draftName,
                            makeDefault: makeDraftDefault
                        )
                        isShowingSaveDraft = false
                    }
                    .buttonStyle(EditorActionButtonStyle(tone: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .padding(24)
            .frame(minWidth: 360)
        }
        .confirmationDialog(
            AppStrings.text("ui.draft.deleteConfirm"),
            isPresented: Binding(
                get: { draftPendingDeletion != nil },
                set: { if !$0 { draftPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.text("ui.draft.delete"), role: .destructive) {
                if let draftPendingDeletion {
                    appModel.deleteOverlayDraft(draftPendingDeletion.id)
                }
                draftPendingDeletion = nil
            }
        } message: {
            Text(draftPendingDeletion?.name ?? "")
        }
    }

    private var accentColorControls: some View {
        let current = appModel.editingOverlayConfiguration.accentHex
        return HStack(spacing: 8) {
            ColorPicker(
                selection: Binding(
                    get: { Color(inspectorHex: current) },
                    set: { color in
                        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else {
                            return
                        }
                        let hex = String(
                            format: "#%02X%02X%02X",
                            Int((min(max(rgb.redComponent, 0), 1) * 255).rounded()),
                            Int((min(max(rgb.greenComponent, 0), 1) * 255).rounded()),
                            Int((min(max(rgb.blueComponent, 0), 1) * 255).rounded())
                        )
                        if appModel.editingOverlayConfiguration.accentHex != hex {
                            appModel.setOverlayAccentHex(hex)
                        }
                    }
                ),
                supportsOpacity: false
            ) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(inspectorHex: current))
                        .frame(width: 20, height: 20)
                        .overlay {
                            Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1)
                        }
                    Text(current)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EditorTheme.text)
            }
            .controlSize(.large)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 9))
            .help(AppStrings.text("ui.overlay.pickAccentColor"))
            .accessibilityLabel(AppStrings.text("ui.overlay.pickAccentColor"))

            Button {
                isShowingRecommendedColors.toggle()
            } label: {
                HStack(spacing: 5) {
                    Text(AppStrings.text("ui.overlay.recommendedColors"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EditorTheme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 6)
                .background(EditorTheme.sidebar, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(EditorTheme.accent.opacity(0.8), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(AppStrings.text("ui.overlay.recommendedColors"))
            .popover(isPresented: $isShowingRecommendedColors, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppStrings.text("ui.overlay.recommendedColors"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(EditorTheme.text)
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 8),
                            count: 2
                        ),
                        spacing: 8
                    ) {
                        ForEach(recommendedAccentColors, id: \.self) { hex in
                            Button {
                                if appModel.editingOverlayConfiguration.accentHex != hex {
                                    appModel.setOverlayAccentHex(hex)
                                }
                                isShowingRecommendedColors = false
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(inspectorHex: hex))
                                        .frame(width: 19, height: 19)
                                        .overlay {
                                            Circle().strokeBorder(
                                                Color.white.opacity(0.5),
                                                lineWidth: 1
                                            )
                                        }
                                    Text(hex)
                                        .font(.system(size: 11, weight: .medium))
                                        .monospacedDigit()
                                    Spacer(minLength: 0)
                                    if current == hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(EditorTheme.accent)
                                    }
                                }
                                .foregroundStyle(EditorTheme.text)
                                .padding(.horizontal, 9)
                                .frame(height: 40)
                                .background(
                                    current == hex ? EditorTheme.raised : EditorTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(hex)
                            .accessibilityAddTraits(current == hex ? [.isSelected] : [])
                        }
                    }
                }
                .padding(14)
                .frame(width: 290)
                .background(EditorTheme.sidebar)
            }
        }
    }

    private var recommendedAccentColors: [String] {
        [
            "#FFFFFF", "#D7FF3F", "#55E6FF", "#FF654F",
            "#FFAD72", "#EFD77E", "#B9D99B", "#88D9C0"
        ]
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EditorTheme.muted)
            VStack(alignment: .leading, spacing: 11) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(EditorTheme.separator.opacity(0.8))
                .frame(height: 1)
                .padding(.top, 5)
        }
    }
}

private struct OverlayLayerCard: View {
    let kind: OverlayElementKind
    let isVisible: Bool
    let isEditing: Bool
    let onToggleVisibility: () -> Void
    let onEdit: () -> Void

    @State private var isHovered = false

    private var foreground: Color {
        if isVisible {
            return Color(red: 0.18, green: 0.16, blue: 0.08)
        }
        return EditorTheme.muted
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onToggleVisibility) {
                VStack(spacing: 5) {
                    Image(systemName: kind.inspectorSymbol)
                        .font(.system(size: 18, weight: .medium))
                        .frame(height: 21)
                    Text(kind.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .foregroundStyle(foreground)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .help(AppStrings.text(
                isVisible ? "ui.overlay.hideLayer" : "ui.overlay.showLayer"
            ))
            .accessibilityLabel(
                AppStrings.text(
                    isVisible ? "ui.overlay.hideLayer" : "ui.overlay.showLayer"
                ) + "：" + kind.displayName
            )

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 25, height: 25)
                    .background(
                        isVisible ? EditorTheme.canvas.opacity(0.13) : EditorTheme.surface,
                        in: Circle()
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isVisible ? EditorTheme.canvas : EditorTheme.text)
            .accessibilityLabel(
                "\(AppStrings.text("ui.overlay.editLayer"))：\(kind.displayName)"
            )
            .help(AppStrings.text("ui.overlay.editLayer"))
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    isVisible
                        ? EditorTheme.highlight
                        : EditorTheme.raised
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isEditing ? EditorTheme.accent : Color.white.opacity(
                        isHovered ? 0.22 : 0.06
                    ),
                    lineWidth: isEditing ? 1.5 : 1
                )
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .animation(.easeOut(duration: 0.16), value: isVisible)
    }
}

private struct InspectorElementEditor: View {
    @EnvironmentObject private var appModel: AppModel
    let element: OverlayElementConfiguration
    let preset: OverlayTemplatePreset
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(element.kind.displayName, systemImage: element.kind.inspectorSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EditorTheme.text)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .smallIcon))
                .accessibilityLabel(AppStrings.text("ui.overlay.closeLayerEditor"))
            }

            if let selectedUnit = element.effectiveMeasurementUnit,
               !element.kind.supportedMeasurementUnits.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.text("ui.overlay.measurementUnit"))
                        .foregroundStyle(EditorTheme.muted)
                    EditorChoiceTabs(
                        options: element.kind.supportedMeasurementUnits,
                        selection: selectedUnit,
                        columns: 2,
                        title: {
                            element.kind == .pace ? "/\($0.symbol)" : $0.symbol
                        },
                        onSelect: {
                            appModel.setOverlayElementMeasurementUnit(element.id, unit: $0)
                        }
                    )
                }
            }

            if element.kind == .clockTime {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.text("ui.overlay.clockDisplay"))
                        .foregroundStyle(EditorTheme.muted)
                    EditorChoiceTabs(
                        options: OverlayClockDisplay.allCases,
                        selection: element.clockDisplay,
                        columns: 3,
                        title: {
                            switch $0 {
                            case .dateTime: AppStrings.text("ui.overlay.clockDateTime")
                            case .date: AppStrings.text("ui.overlay.clockDate")
                            case .time: AppStrings.text("ui.overlay.clockTimeOnly")
                            }
                        },
                        onSelect: {
                            appModel.setOverlayElementClockDisplay(element.id, display: $0)
                        }
                    )
                }
            }

            if element.kind == .elapsedTime {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.text("ui.overlay.durationDisplay"))
                        .foregroundStyle(EditorTheme.muted)
                    EditorChoiceTabs(
                        options: OverlayDurationDisplay.allCases,
                        selection: element.durationDisplay,
                        columns: 2,
                        title: {
                            switch $0 {
                            case .adaptive: AppStrings.text("ui.overlay.durationAdaptive")
                            case .hoursMinutesSeconds: "HH:MM:SS"
                            }
                        },
                        onSelect: {
                            appModel.setOverlayElementDurationDisplay(element.id, display: $0)
                        }
                    )
                }
            }

            InspectorElementSlider(
                title: AppStrings.text("ui.overlay.positionX"),
                value: element.frame.x,
                range: 0...max(0, 1 - element.frame.width)
            ) { value in
                var frame = element.frame
                frame.x = value
                appModel.setOverlayElementFrame(element.id, frame: frame)
            }
            InspectorElementSlider(
                title: AppStrings.text("ui.overlay.positionY"),
                value: element.frame.y,
                range: 0...max(0, 1 - element.frame.height)
            ) { value in
                var frame = element.frame
                frame.y = value
                appModel.setOverlayElementFrame(element.id, frame: frame)
            }
            InspectorElementSlider(
                title: AppStrings.text("ui.overlay.width"),
                value: element.frame.width,
                range: 0.08...max(0.08, min(0.8, 1 - element.frame.x))
            ) { value in
                var frame = element.frame
                frame.width = value
                appModel.setOverlayElementFrame(element.id, frame: frame)
            }
            InspectorElementSlider(
                title: AppStrings.text("ui.overlay.height"),
                value: element.frame.height,
                range: 0.06...max(0.06, min(0.8, 1 - element.frame.y))
            ) { value in
                var frame = element.frame
                frame.height = value
                appModel.setOverlayElementFrame(element.id, frame: frame)
            }
            InspectorElementSlider(
                title: AppStrings.text("ui.overlay.opacity"),
                value: element.opacity,
                range: 0...1
            ) { appModel.setOverlayElementOpacity(element.id, opacity: $0) }
            InspectorElementSlider(
                title: AppStrings.text("ui.overlay.backgroundOpacity"),
                value: element.backgroundOpacity ?? preset.defaultBackgroundOpacity,
                range: 0...1
            ) { appModel.setOverlayElementBackgroundOpacity(element.id, opacity: $0) }

            if element.kind != .route {
                InspectorElementSlider(
                    title: AppStrings.text("ui.overlay.textSize"),
                    value: element.textScale,
                    range: 0.5...2
                ) { appModel.setOverlayElementTextScale(element.id, scale: $0) }
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            EditorTheme.separator.frame(height: 1)
        }
    }
}

private struct InspectorElementSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(EditorTheme.muted)
                .frame(width: 82, alignment: .leading)
            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in onChange(newValue) }
                ),
                in: range
            )
            .accessibilityLabel(title)
            Text("\(Int((value * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(EditorTheme.text)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

private extension OverlayElementKind {
    var inspectorSymbol: String {
        switch self {
        case .route: "point.topleft.down.curvedto.point.bottomright.up"
        case .pace: "speedometer"
        case .distance: "figure.run"
        case .elapsedTime: "timer"
        case .clockTime: "calendar"
        case .heartRate: "heart.fill"
        case .cadence: "figure.run.circle"
        case .power: "bolt.fill"
        case .altitude: "mountain.2"
        case .ascent: "arrow.up.right"
        case .calories: "flame.fill"
        case .progress: "chart.bar.fill"
        case .elevationProfile: "chart.xyaxis.line"
        }
    }
}

private extension Color {
    init(inspectorHex hex: String) {
        let text = hex.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted
        )
        let value = UInt64(text, radix: 16) ?? 0xFFFFFF
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
