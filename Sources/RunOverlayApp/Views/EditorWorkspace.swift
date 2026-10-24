import AppKit
import AVFoundation
import RunOverlayCore
import SwiftUI
import UniformTypeIdentifiers

private final class PlaybackSurfaceView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建视频预览")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct VideoPlaybackSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlaybackSurfaceView {
        let view = PlaybackSurfaceView(frame: .zero)
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlaybackSurfaceView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }

    static func dismantleNSView(_ view: PlaybackSurfaceView, coordinator: ()) {
        view.playerLayer.player = nil
    }
}

private struct OverlayResizeChange {
    let size: CGSize
    let anchor: CGPoint
}

private struct OverlayInteraction: Equatable {
    let elementID: UUID
    let handle: OverlayResizeHandle?
    var translation: CGSize
}

@MainActor
private enum OverlayCursor {
    static let northWestSouthEast = diagonalCursor(
        named: "arrow.up.left.and.arrow.down.right"
    )
    static let northEastSouthWest = diagonalCursor(
        named: "arrow.up.right.and.arrow.down.left"
    )

    static func cursor(for handle: OverlayResizeHandle?) -> NSCursor {
        switch handle {
        case .leading, .trailing: .resizeLeftRight
        case .top, .bottom: .resizeUpDown
        case .topLeading, .bottomTrailing: northWestSouthEast
        case .topTrailing, .bottomLeading: northEastSouthWest
        case nil: .openHand
        }
    }

    private static func diagonalCursor(named symbol: String) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()
        if let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            icon.draw(in: NSRect(origin: .zero, size: size))
        }
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }
}

struct EditorWorkspace: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isDropTargeted = false
    let onEnterFullscreen: () -> Void
    let onShowSmartEdit: () -> Void
    var smartEditExportQueue: SmartEditBackgroundExportQueue?

    var body: some View {
        VStack(spacing: 0) {
            workspaceToolbar
            Rectangle()
                .fill(EditorTheme.separator)
                .frame(height: 1)
            ZStack(alignment: .bottom) {
                if let video = appModel.selectedVideo {
                    VideoCanvas(
                        video: video,
                        isFullscreenPreview: false,
                        onEnterFullscreen: onEnterFullscreen
                    )
                } else {
                    EmptyEditorView()
                }

                if appModel.selectedVideo != nil {
                    HStack {
                        SnapshotControls()
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 30)
                    .padding(.bottom, 14)
                }

                HStack {
                    Spacer(minLength: 0)
                    historyControls
                }
                .padding(.trailing, 16)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let video = appModel.selectedVideo {
                Rectangle()
                    .fill(EditorTheme.separator)
                    .frame(height: 1)
                TimelinePlaceholder(video: video)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EditorTheme.canvas)
        .contentShape(Rectangle())
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        EditorTheme.accent,
                        style: StrokeStyle(lineWidth: 3, dash: [10, 6])
                    )
                    .background(EditorTheme.accent.opacity(0.08))
                    .overlay {
                        Label(
                            AppStrings.text("ui.drag.dropHint"),
                            systemImage: "square.and.arrow.down"
                        )
                        .font(.title3.weight(.semibold))
                        .padding(18)
                        .background(.regularMaterial, in: Capsule())
                    }
                    .padding(12)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onDrop(
            of: [.fileURL, .url],
            isTargeted: $isDropTargeted,
            perform: { providers in
                guard !appModel.exportBatchHasStarted else {
                    return false
                }
                return handleFileDrop(providers)
            }
        )
    }

    private var historyControls: some View {
        HStack(spacing: 4) {
            Button {
                appModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 32, height: 30)
                    .contentShape(Rectangle())
                    .foregroundStyle(
                        appModel.canUndo ? Color.white : EditorTheme.muted.opacity(0.55)
                    )
            }
            .buttonStyle(EditorActionButtonStyle(tone: .quiet, size: .icon))
            .keyboardShortcut("z")
            .disabled(!appModel.canUndo)
            .accessibilityLabel(AppStrings.text("ui.undo"))
            .help(appModel.undoActions.first.map {
                "\(AppStrings.text("ui.undo"))：\($0)"
            } ?? AppStrings.text("ui.undo"))

            Button {
                appModel.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 32, height: 30)
                    .contentShape(Rectangle())
                    .foregroundStyle(
                        appModel.canRedo ? Color.white : EditorTheme.muted.opacity(0.55)
                    )
            }
            .buttonStyle(EditorActionButtonStyle(tone: .quiet, size: .icon))
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!appModel.canRedo)
            .accessibilityLabel(AppStrings.text("ui.redo"))
            .help(appModel.redoActions.first.map {
                "\(AppStrings.text("ui.redo"))：\($0)"
            } ?? AppStrings.text("ui.redo"))
        }
        .font(.system(size: 15, weight: .semibold))
        .padding(4)
        .background(EditorTheme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 9))
    }

    private var workspaceToolbar: some View {
        VStack(spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    aspectRatioTabs
                    resolutionTabs
                    Spacer(minLength: 4)
                    languageTabs
                    smartEditButton
                    exportButton
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(spacing: 3) {
                    HStack(spacing: 8) {
                        aspectRatioTabs
                        Spacer(minLength: 4)
                        smartEditButton
                        exportButton
                    }
                    HStack(spacing: 8) {
                        resolutionTabs
                        Spacer(minLength: 4)
                        languageTabs
                    }
                }
            }

            if !appModel.exportJobs.isEmpty {
                Button {
                    appModel.presentExportQueue()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(
                                systemName: appModel.exportBatchIsFinished
                                    ? (appModel.exportBatchUnsuccessfulCount > 0
                                        ? "exclamationmark.circle.fill"
                                        : "checkmark.circle.fill")
                                    : "arrow.up.forward.square"
                            )
                            Text(
                                AppStrings.text(
                                    appModel.exportBatchIsFinished
                                        ? (appModel.exportBatchUnsuccessfulCount > 0
                                            ? "ui.export.finishedWithErrors"
                                            : "ui.export.finished")
                                        : "ui.export.exporting"
                                )
                            )
                            Text(
                                AppStrings.format(
                                    "ui.export.progressPercent",
                                    Int((appModel.exportBatchProgress * 100).rounded())
                                )
                            )
                            .monospacedDigit()
                            Spacer(minLength: 0)
                        }
                        ProgressView(value: appModel.exportBatchProgress)
                            .tint(EditorTheme.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background(EditorTheme.surface.opacity(0.82), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(EditorTheme.accent.opacity(0.65), lineWidth: 1)
                }
                .help(AppStrings.text("ui.export.openProgress"))
            } else if let smartEditExportQueue {
                Button {
                    if smartEditExportQueue.isComplete,
                       smartEditExportQueue.failureMessage == nil,
                       let url = smartEditExportQueue.outputURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else if smartEditExportQueue.isComplete {
                        onShowSmartEdit()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: smartEditExportQueue.isComplete
                                ? (smartEditExportQueue.failureMessage == nil
                                    ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                : "sparkles.rectangle.stack")
                            Text(AppStrings.format(
                                smartEditExportQueue.isComplete
                                    ? "smartEdit.backgroundExportComplete"
                                    : "smartEdit.exportingBackground",
                                smartEditExportQueue.draft.name
                            ))
                            .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        ProgressView(value: smartEditExportQueue.progress)
                            .tint(EditorTheme.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background(EditorTheme.surface.opacity(0.82), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(EditorTheme.accent.opacity(0.65), lineWidth: 1)
                }
                .help(AppStrings.text("smartEdit.backgroundExportIndicatorHelp"))
            }
        }
        .font(.caption.weight(.medium))
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(EditorTheme.sidebar)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var aspectRatioTabs: some View {
        HStack(spacing: 4) {
            Image(systemName: "aspectratio")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            EditorInlineTabs(
                options: {
                    var ratios: [ExportAspectRatio] = [
                        .source, .landscape16x9, .portrait9x16,
                        .landscape4x3, .portrait3x4
                    ]
                    let selected = appModel.project.exportSettings.aspectRatio
                    if !ratios.contains(selected) { ratios.append(selected) }
                    return ratios
                }(),
                selection: appModel.project.exportSettings.aspectRatio,
                title: aspectTabTitle,
                onSelect: { appModel.setExportAspectRatio($0) },
                helpText: { $0.displayName }
            )
            .accessibilityLabel(AppStrings.text("ui.workspace.aspectRatio"))
        }
        .help(AppStrings.text("ui.workspace.aspectRatioHelp"))
    }

    private var resolutionTabs: some View {
        Label {
            EditorInlineTabs(
                options: [480, 720, 1_080, 1_440, 2_160],
                selection: appModel.project.exportSettings.maximumHeight,
                title: { "\($0)p" },
                onSelect: { appModel.setExportMaximumHeight($0) }
            )
            .accessibilityLabel(AppStrings.text("ui.export.resolution"))
        } icon: {
            Image(systemName: "viewfinder")
                .foregroundStyle(.secondary)
        }
        .help(AppStrings.text("ui.workspace.resolutionHelp"))
    }

    private var languageTabs: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            EditorInlineTabs(
                options: RunOverlayLanguage.allCases,
                selection: appModel.selectedLanguage,
                title: languageTabTitle,
                onSelect: { appModel.setLanguage($0) },
                helpText: { $0.displayName }
            )
            .accessibilityLabel(AppStrings.text("ui.workspace.language"))
        }
        .help(AppStrings.text("ui.workspace.languageHelp"))
    }

    private var exportButton: some View {
        Button {
            appModel.presentExportQueue()
        } label: {
            Label(
                AppStrings.text("ui.export.batch"),
                systemImage: "square.and.arrow.up.on.square"
            )
        }
        .buttonStyle(EditorActionButtonStyle(tone: .primary, size: .compact))
        .fixedSize()
        .disabled(
            appModel.project.videos.isEmpty &&
                appModel.exportJobs.isEmpty
        )
        .help(AppStrings.text("ui.export.allHelp"))
    }

    private var smartEditButton: some View {
        Button(action: onShowSmartEdit) {
            Label(
                AppStrings.text("smartEdit.open"),
                systemImage: "sparkles.rectangle.stack"
            )
        }
        .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
        .fixedSize()
        .help(AppStrings.text("smartEdit.openHelp"))
    }

    private func aspectTabTitle(_ ratio: ExportAspectRatio) -> String {
        switch ratio {
        case .source: AppStrings.text("ui.workspace.aspectRatio.sourceShort")
        case .landscape16x9: "16:9"
        case .portrait9x16: "9:16"
        case .landscape4x3: "4:3"
        case .portrait3x4: "3:4"
        case .square: "1:1"
        case .portrait4x5: "4:5"
        }
    }

    private func languageTabTitle(_ language: RunOverlayLanguage) -> String {
        switch language {
        case .system: AppStrings.text("ui.workspace.language.systemShort")
        case .chineseSimplified: AppStrings.text("ui.workspace.language.chineseShort")
        case .english: "EN"
        case .japanese: AppStrings.text("ui.workspace.language.japaneseShort")
        }
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else {
            return false
        }

        let collector = DroppedURLCollector()
        let group = DispatchGroup()
        for provider in providers {
            guard let typeIdentifier = dropTypeIdentifier(for: provider) else {
                continue
            }
            group.enter()
            provider.loadItem(
                forTypeIdentifier: typeIdentifier,
                options: nil
            ) { item, _ in
                if let url = Self.droppedFileURL(from: item) {
                    collector.append(url)
                }
                group.leave()
            }
        }

        guard providers.contains(where: {
            dropTypeIdentifier(for: $0) != nil
        }) else {
            return false
        }

        group.notify(queue: .main) {
            let urls = collector.urls
            Task { @MainActor in
                guard !urls.isEmpty else {
                    appModel.presentedError = PresentedError(
                        title: AppStrings.text("ui.drag.readFailureTitle"),
                        message: AppStrings.text("ui.drag.readFailureMessage")
                    )
                    return
                }
                appModel.importDroppedURLs(urls)
            }
        }
        return true
    }

    private func dropTypeIdentifier(for provider: NSItemProvider) -> String? {
        [UTType.fileURL, UTType.url].first {
            provider.hasItemConformingToTypeIdentifier($0.identifier)
        }?.identifier
    }

    nonisolated private static func droppedFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url.isFileURL ? url : nil
        }
        if let url = item as? NSURL {
            let value = url as URL
            return value.isFileURL ? value : nil
        }
        if let data = item as? Data {
            if let url = URL(dataRepresentation: data, relativeTo: nil) {
                return url.isFileURL ? url : nil
            }
            if let path = String(data: data, encoding: .utf8),
               let url = URL(string: path.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return url.isFileURL ? url : nil
            }
        }
        if let path = item as? String {
            if let url = URL(string: path), url.isFileURL {
                return url
            }
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}

private struct SnapshotControls: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                appModel.presentSaveSnapshotPanel()
            } label: {
                Label(AppStrings.text("ui.snapshot.save"), systemImage: "camera")
            }
            .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
            .help(AppStrings.text("ui.snapshot.saveHint"))
            .disabled(appModel.player.currentItem == nil || appModel.isSavingSnapshot)

            Button {
                appModel.presentCoverEditor()
            } label: {
                Label(AppStrings.text("ui.cover.edit"), systemImage: "photo.badge.plus")
            }
            .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
            .help(AppStrings.text("ui.cover.editHint"))
            .disabled(appModel.player.currentItem == nil)

            Toggle(
                AppStrings.text("ui.snapshot.includeDataLayer"),
                isOn: $appModel.snapshotIncludesDataLayer
            )
            .toggleStyle(.checkbox)
            .help(AppStrings.text("ui.snapshot.includeDataLayerHint"))
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(EditorTheme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 9))
    }
}

private final class DroppedURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }
}

struct FullscreenPreviewView: View {
    @EnvironmentObject private var appModel: AppModel
    let video: VideoItem
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VideoCanvas(
                video: video,
                isFullscreenPreview: true,
                onEnterFullscreen: {}
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 14) {
                Button {
                    appModel.togglePlayback()
                } label: {
                    Image(systemName: appModel.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .icon))
                .keyboardShortcut(.return, modifiers: [])
                .help(
                    AppStrings.text(
                        appModel.isPlaying
                            ? "ui.timeline.pauseHint"
                            : "ui.timeline.playHint"
                    )
                )
                .accessibilityLabel(
                    AppStrings.text(
                        appModel.isPlaying ? "ui.timeline.pause" : "ui.timeline.play"
                    )
                )
                .disabled(appModel.player.currentItem == nil)

                Text(RunOverlayFormatters.duration(appModel.playbackTime))
                    .monospacedDigit()

                Slider(
                    value: Binding(
                        get: { appModel.playbackTime },
                        set: { appModel.seek(to: $0) }
                    ),
                    in: 0...max(video.metadata.durationSeconds, 1)
                )
                .disabled(appModel.player.currentItem == nil)
                .accessibilityLabel(AppStrings.text("ui.timeline.playback"))
                .help(AppStrings.text("ui.timeline.seekHint"))

                Text(RunOverlayFormatters.duration(video.metadata.durationSeconds))
                    .monospacedDigit()

                SnapshotControls()

                Button(action: onExit) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .icon))
                .keyboardShortcut(.escape, modifiers: [])
                .help(AppStrings.text("ui.preview.exitFullscreen"))
                .accessibilityLabel(AppStrings.text("ui.preview.exitFullscreen"))
            }
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.black.opacity(0.86))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .preferredColorScheme(.dark)
    }
}

struct VideoCanvas: View {
    @EnvironmentObject private var appModel: AppModel
    let video: VideoItem
    let isFullscreenPreview: Bool
    let onEnterFullscreen: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let plan = appModel.outputPlan(for: video)
            let canvasSize = fittedSize(
                content: plan.outputDimensions,
                available: CGSize(
                    width: max(1, proxy.size.width - (isFullscreenPreview ? 0 : 48)),
                    height: max(1, proxy.size.height - (isFullscreenPreview ? 0 : 48))
                )
            )
            let fittedVideoSize = fittedSize(
                content: plan.rotatedDimensions,
                available: canvasSize
            )
            let playbackSize = CGSize(
                width: video.rotation.swapsDimensions
                    ? fittedVideoSize.height : fittedVideoSize.width,
                height: video.rotation.swapsDimensions
                    ? fittedVideoSize.width : fittedVideoSize.height
            )

            ZStack {
                Color.black

                if appModel.player.currentItem != nil {
                    VideoPlaybackSurface(player: appModel.player)
                        .frame(width: playbackSize.width, height: playbackSize.height)
                        .rotationEffect(.degrees(Double(video.rotation.rawValue)))
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .accessibilityLabel(AppStrings.text("ui.timeline.videoPreview"))
                } else if let thumbnail = appModel.videoThumbnails[video.id] {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: playbackSize.width, height: playbackSize.height)
                        .rotationEffect(.degrees(Double(video.rotation.rawValue)))
                        .frame(width: canvasSize.width, height: canvasSize.height)
                } else if appModel.missingResourceVideoIDs.contains(video.id) {
                    Label(
                        AppStrings.text("ui.preview.sourceMissing"),
                        systemImage: "video.slash"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(EditorTheme.muted)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                } else {
                    ProgressView(AppStrings.text("ui.preview.generating"))
                        .tint(.white)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                OverlayEditor(
                    configuration: appModel.effectiveOverlayConfiguration,
                    videoTextLanguage: appModel.project.exportSettings.videoTextLanguage,
                    sample: appModel.currentActivitySample,
                    activityProgress: appModel.currentActivityProgress,
                    activityStart: appModel.project.activitySource?.timeRange?.start,
                    clockTime: appModel.currentVideoClockTime,
                    route: appModel.routeCoordinates,
                    elevationProfile: appModel.elevationProfile,
                    selectedElementID: isFullscreenPreview
                        ? nil
                        : appModel.selectedOverlayElementID,
                    isInteractive: !isFullscreenPreview,
                    canvasSize: canvasSize,
                    onSelect: appModel.selectOverlayElement,
                    onMove: { id, delta in
                        appModel.moveOverlayElement(
                            id,
                            by: delta,
                            canvasSize: canvasSize
                        )
                    },
                    onResize: { id, delta in
                        appModel.resizeOverlayElement(
                            id,
                            by: delta.size,
                            canvasSize: canvasSize,
                            anchor: delta.anchor
                        )
                    }
                )
            }
            .clipShape(RoundedRectangle(
                cornerRadius: isFullscreenPreview ? 0 : 10
            ))
            .frame(width: canvasSize.width, height: canvasSize.height)
            .overlay(alignment: .topTrailing) {
                if !isFullscreenPreview {
                    Button(action: onEnterFullscreen) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(.black.opacity(0.65), in: RoundedRectangle(
                                cornerRadius: 7
                            ))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .icon))
                    .padding(10)
                    .help(AppStrings.text("ui.preview.fullscreen"))
                    .accessibilityLabel(AppStrings.text("ui.preview.fullscreen"))
                }
            }
            .overlay(alignment: .topLeading) {
                if !isFullscreenPreview {
                    Text(
                        AppStrings.text(
                            plan.outputDimensions.isPortrait
                                ? "ui.video.portrait"
                                : "ui.video.landscape"
                        )
                    )
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.58), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(10)
                }
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .overlay(alignment: .topTrailing) {
                if !isFullscreenPreview {
                    EditorInlineTabs(
                        options: [VideoTextLanguage.chinese, .english],
                        selection: appModel.project.exportSettings.videoTextLanguage,
                        title: {
                            AppStrings.text(
                                $0 == .chinese
                                    ? "ui.videoText.chinese" : "ui.videoText.english"
                            )
                        },
                        onSelect: { appModel.setVideoTextLanguage($0) }
                    )
                    .padding(4)
                    .background(EditorTheme.surface, in: Capsule())
                    .padding(.top, 8)
                    .padding(.trailing, 14)
                    .help(AppStrings.text("ui.videoText.language"))
                    .accessibilityLabel(AppStrings.text("ui.videoText.language"))
                }
            }
        }
    }

    private func fittedSize(
        content: PixelDimensions,
        available: CGSize
    ) -> CGSize {
        let contentAspect = CGFloat(content.width) / CGFloat(max(content.height, 1))
        let availableAspect = available.width / max(available.height, 1)

        if contentAspect > availableAspect {
            return CGSize(
                width: available.width,
                height: available.width / contentAspect
            )
        }
        return CGSize(
            width: available.height * contentAspect,
            height: available.height
        )
    }
}

private struct OverlayEditor: View {
    let configuration: OverlayConfiguration
    let videoTextLanguage: VideoTextLanguage
    let sample: ActivitySample?
    let activityProgress: ActivityProgress?
    let activityStart: Date?
    let clockTime: Date?
    let route: [GeoCoordinate]
    let elevationProfile: ElevationProfile
    let selectedElementID: UUID?
    let isInteractive: Bool
    let canvasSize: CGSize
    let onSelect: (UUID) -> Void
    let onMove: (UUID, CGSize) -> Void
    let onResize: (UUID, OverlayResizeChange) -> Void

    @GestureState private var interaction: OverlayInteraction?

    private var accent: Color {
        Color(overlayHex: configuration.accentHex)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(configuration.elements.filter(\.isVisible)) { element in
                    OverlayElementView(
                        element: element,
                        preset: configuration.preset,
                        videoTextLanguage: videoTextLanguage,
                        sample: sample,
                        activityProgress: activityProgress,
                        activityStart: activityStart,
                        clockTime: clockTime,
                        route: route,
                        elevationProfile: elevationProfile,
                        accent: accent,
                        isSelected: selectedElementID == element.id ||
                            interaction?.elementID == element.id,
                        canvasSize: proxy.size,
                        interaction: interaction?.elementID == element.id
                            ? interaction
                            : nil
                    )
                    .allowsHitTesting(false)
                }

                if isInteractive {
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover(coordinateSpace: .local) { phase in
                            switch phase {
                            case let .active(point):
                                guard let hit = target(
                                    at: point,
                                    canvasSize: canvasSize
                                ) else {
                                    NSCursor.arrow.set()
                                    return
                                }
                                OverlayCursor.cursor(for: hit.handle).set()
                            case .ended:
                                NSCursor.arrow.set()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .updating($interaction) { value, state, _ in
                                guard let target = target(
                                    at: value.startLocation,
                                    canvasSize: canvasSize
                                ) else {
                                    return
                                }
                                state = OverlayInteraction(
                                    elementID: target.elementID,
                                    handle: target.handle,
                                    translation: value.translation
                                )
                            }
                            .onEnded { value in
                                guard let target = target(
                                    at: value.startLocation,
                                    canvasSize: canvasSize
                                ) else {
                                    return
                                }
                                onSelect(target.elementID)
                                guard hypot(
                                    value.translation.width,
                                    value.translation.height
                                ) > 2 else {
                                    return
                                }
                                if let handle = target.handle {
                                    onResize(
                                        target.elementID,
                                        OverlayResizeChange(
                                            size: value.translation,
                                            anchor: handle.anchor
                                        )
                                    )
                                } else {
                                    onMove(target.elementID, value.translation)
                                }
                            }
                        )
                }
            }
        }
        .foregroundStyle(.white)
        .frame(width: canvasSize.width, height: canvasSize.height)
        .onDisappear {
            NSCursor.arrow.set()
        }
    }

    private func target(
        at point: CGPoint,
        canvasSize: CGSize
    ) -> OverlayHitTarget? {
        OverlayHitTester.target(
            at: point,
            in: canvasSize,
            elements: configuration.elements,
            selectedElementID: selectedElementID
        )
    }
}

private struct OverlayElementView: View {
    let element: OverlayElementConfiguration
    let preset: OverlayTemplatePreset
    let videoTextLanguage: VideoTextLanguage
    let sample: ActivitySample?
    let activityProgress: ActivityProgress?
    let activityStart: Date?
    let clockTime: Date?
    let route: [GeoCoordinate]
    let elevationProfile: ElevationProfile
    let accent: Color
    let isSelected: Bool
    let canvasSize: CGSize
    let interaction: OverlayInteraction?

    var body: some View {
        let width = max(1, CGFloat(element.frame.width) * canvasSize.width)
        let height = max(1, CGFloat(element.frame.height) * canvasSize.height)
        let resizeWidth = interaction?.handle != nil
            ? (interaction?.translation.width ?? 0) *
                (interaction?.handle?.anchor.x ?? 0)
            : 0
        let resizeHeight = interaction?.handle != nil
            ? (interaction?.translation.height ?? 0) *
                (interaction?.handle?.anchor.y ?? 0)
            : 0
        let previewWidth = max(1, width + resizeWidth)
        let previewHeight = max(1, height + resizeHeight)

        ZStack(alignment: .bottomTrailing) {
            elementContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(
                    element.kind == .progress ||
                        element.kind == .elevationProfile ||
                        preset == .stadiumLive ||
                        preset == .runningFocus
                        ? 0
                        : preset == .minimal
                            ? 6
                            : min(10, max(3, previewWidth * 0.06))
                )
                .background(backgroundStyle)

            if isSelected {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        accent,
                        style: StrokeStyle(
                            lineWidth: 2,
                            dash: interaction != nil ? [] : [5, 3]
                        )
                    )
            }
        }
        .frame(
            width: previewWidth,
            height: previewHeight
        )
        .opacity(element.opacity)
        .offset(
            x: CGFloat(element.frame.x) * canvasSize.width +
                (interaction?.handle == nil
                    ? interaction?.translation.width ?? 0
                    : (interaction?.handle?.anchor.x ?? 0) < 0
                        ? interaction?.translation.width ?? 0
                        : 0),
            y: CGFloat(element.frame.y) * canvasSize.height +
                (interaction?.handle == nil
                    ? interaction?.translation.height ?? 0
                    : (interaction?.handle?.anchor.y ?? 0) < 0
                        ? interaction?.translation.height ?? 0
                        : 0)
        )
    }

    @ViewBuilder
    private var elementContent: some View {
        if element.kind == .progress {
            RunningProgressBar(
                progress: activityProgress,
                accent: accent,
                textScale: element.textScale
            )
        } else if element.kind == .elevationProfile {
            ElevationProfileGlyph(
                profile: elevationProfile,
                current: sample,
                unit: element.effectiveMeasurementUnit ?? .meters,
                accent: accent,
                language: videoTextLanguage,
                textScale: element.textScale
            )
        } else if preset == .runningFocus {
            runningFocusContent
        } else if preset == .stadiumLive {
            stadiumContent
        } else if element.kind == .route {
            RouteGlyph(
                coordinates: route,
                currentCoordinate: sample?.coordinate,
                accent: accent
            )
        } else if element.kind == .clockTime {
            Text(RunOverlayFormatters.clock(clockTime, display: element.clockDisplay))
                .font(.system(
                    size: fittedClockFontSize(
                        RunOverlayFormatters.clock(clockTime, display: element.clockDisplay),
                        width: max(
                            1,
                            CGFloat(element.frame.width) * canvasSize.width -
                                (preset == .minimal ? 12 : 20)
                        ),
                        proposed: 23 * element.textScale
                    ),
                    weight: .bold,
                    design: .rounded
                ))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .monospacedDigit()
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .leading
            )
        } else {
            (
                Text(metricValue)
                    .font(.system(
                        size: 24 * element.textScale,
                        weight: .bold,
                        design: .rounded
                    ))
                + Text(metricUnit.isEmpty ? "" : " \(metricUnit)")
                    .font(.system(size: 9 * element.textScale, weight: .bold))
                    .foregroundColor(accent)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.25)
            .monospacedDigit()
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .leading
            )
        }
    }

    @ViewBuilder
    private var runningFocusContent: some View {
        Group {
            if element.kind == .route {
                RouteGlyph(
                    coordinates: route,
                    currentCoordinate: sample?.coordinate,
                    accent: .white
                )
                .padding(5)
            } else if element.kind == .clockTime {
                GeometryReader { geometry in
                    let value = RunningFocusStyle.value(
                        for: .clockTime,
                        sample: sample,
                        activityStart: activityStart,
                        clockTime: clockTime,
                        clockDisplay: element.clockDisplay
                    )
                    Text(value)
                        .font(.system(
                            size: fittedRunningFocusFontSize(
                                value,
                                width: max(1, geometry.size.width - 8),
                                proposed: max(
                                    10,
                                    geometry.size.height * 0.32 * element.textScale
                                )
                            ),
                            weight: .semibold,
                            design: .rounded
                        ))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                GeometryReader { geometry in
                    let value = RunningFocusStyle.value(
                        for: element.kind,
                        sample: sample,
                        activityStart: activityStart,
                        clockTime: clockTime,
                        measurementUnit: element.effectiveMeasurementUnit,
                        clockDisplay: element.clockDisplay,
                        durationDisplay: element.durationDisplay
                    )
                    let label = RunningFocusStyle.label(
                        for: element.kind,
                        language: videoTextLanguage,
                        measurementUnit: element.effectiveMeasurementUnit
                    )
                    let availableWidth = max(1, geometry.size.width - 8)
                    let valueSize = fittedRunningFocusFontSize(
                        value,
                        width: availableWidth,
                        proposed: max(12, geometry.size.height * 0.52 * element.textScale)
                    )
                    let labelSize = fittedRunningFocusFontSize(
                        label,
                        width: availableWidth,
                        proposed: max(8, geometry.size.height * 0.18 * element.textScale)
                    )
                    VStack(spacing: max(2, geometry.size.height * 0.07)) {
                        Text(value)
                            .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .fixedSize(horizontal: true, vertical: false)
                        Text(label)
                            .font(.system(size: labelSize, weight: .medium))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .shadow(color: .black.opacity(0.72), radius: 3, x: 0, y: 1)
    }

    @ViewBuilder
    private var stadiumContent: some View {
        if element.kind == .route {
            ZStack {
                RouteGlyph(
                    coordinates: route,
                    currentCoordinate: sample?.coordinate,
                    accent: accent
                )
                .padding(8)

                HStack {
                    Rectangle().frame(width: 1, height: 12)
                    Spacer()
                    Rectangle().frame(width: 1, height: 12)
                }
                .foregroundStyle(.white.opacity(0.85))
            }
        } else {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let rightAligned = element.kind == .altitude ||
                    element.kind == .distance || element.kind == .clockTime
                let horizontalPadding = min(12, max(2, width * 0.035))

                VStack(alignment: rightAligned ? .trailing : .leading, spacing: 0) {
                    if element.kind == .heartRate {
                        Text("♥")
                            .font(.system(
                                size: max(8, height * 0.23 * element.textScale),
                                weight: .bold
                            ))
                            .frame(
                                width: max(15, height * 0.46),
                                height: max(15, height * 0.46)
                            )
                            .background(.gray.opacity(0.55), in: Circle())
                        Spacer(minLength: 0)
                        Text(StadiumLiveStyle.value(
                            for: element.kind,
                            sample: sample,
                            clockTime: clockTime,
                            activityStart: activityStart,
                            measurementUnit: element.effectiveMeasurementUnit,
                            clockDisplay: element.clockDisplay,
                            durationDisplay: element.durationDisplay
                        ))
                        .font(.system(
                            size: max(8, height * 0.38 * element.textScale),
                            weight: .semibold
                        ))
                        .lineLimit(1)
                        .minimumScaleFactor(0.25)
                        .monospacedDigit()
                    } else {
                        if element.kind != .clockTime {
                            Text(StadiumLiveStyle.label(
                                for: element.kind,
                                language: videoTextLanguage
                            ))
                                .font(.system(
                                    size: max(7, height * 0.19 * element.textScale),
                                    weight: .semibold
                                ))
                                .lineLimit(1)
                                .minimumScaleFactor(0.25)
                        }
                        Spacer(minLength: 0)
                        Text(StadiumLiveStyle.value(
                            for: element.kind,
                            sample: sample,
                            clockTime: clockTime,
                            activityStart: activityStart,
                            measurementUnit: element.effectiveMeasurementUnit,
                            clockDisplay: element.clockDisplay,
                            durationDisplay: element.durationDisplay
                        ))
                        .font(.system(
                            size: element.kind == .clockTime
                                ? fittedClockFontSize(
                                    StadiumLiveStyle.value(
                                        for: element.kind,
                                        sample: sample,
                                        clockTime: clockTime,
                                        activityStart: activityStart,
                                        measurementUnit: element.effectiveMeasurementUnit,
                                        clockDisplay: element.clockDisplay,
                                        durationDisplay: element.durationDisplay
                                    ),
                                    width: max(1, width - horizontalPadding * 2),
                                    proposed: max(12, height * 0.70) * element.textScale
                                )
                                : max(8, height * 0.46 * element.textScale),
                            weight: .semibold
                        ))
                        .lineLimit(1)
                        .minimumScaleFactor(element.kind == .clockTime ? 1 : 0.25)
                        .fixedSize(horizontal: element.kind == .clockTime, vertical: false)
                        .monospacedDigit()
                    }
                }
                .frame(
                    width: max(1, width - horizontalPadding * 2),
                    height: max(1, height - 4),
                    alignment: rightAligned ? .trailing : .leading
                )
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 2)
                .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var backgroundStyle: some View {
        Group {
            if preset == .runningFocus {
                if element.backgroundOpacity != nil {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black)
                } else {
                    Color.clear
                }
            } else if preset == .stadiumLive {
                if element.kind == .route {
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.34, blue: 0.38),
                            Color(red: 0.65, green: 0.68, blue: 0.72)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else if element.backgroundOpacity != nil {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black)
                } else {
                    Color.clear
                }
            } else if preset == .minimal {
                Color.black
            } else {
                RoundedRectangle(cornerRadius: backgroundCornerRadius)
                    .fill(.black)
                    .overlay(alignment: .top) {
                        if preset == .technology {
                            Rectangle()
                                .fill(accent)
                                .frame(height: 2)
                        }
                    }
            }
        }
        .opacity(
            element.backgroundOpacity ??
                preset.defaultBackgroundOpacity
        )
    }

    private var backgroundCornerRadius: CGFloat {
        switch preset {
        case .runningFocus: 8
        case .minimal: 0
        case .technology: 2
        case .nightRun: 12
        case .stadiumLive: 0
        case .sport, .track, .finishLine, .trail: 8
        }
    }

    private var metricValue: String {
        switch element.kind {
        case .pace:
            guard let pace = OverlayMeasurementFormatter.pace(
                speedMetersPerSecond: sample?.speedMetersPerSecond,
                unit: element.effectiveMeasurementUnit ?? .kilometers
            ) else {
                return "—:—"
            }
            return String(format: "%d:%02d", pace.minutes, pace.seconds)
        case .distance:
            return OverlayMeasurementFormatter.distance(
                meters: sample?.distanceMeters,
                unit: element.effectiveMeasurementUnit ?? .kilometers
            ) ?? "0.00"
        case .elapsedTime:
            return RunOverlayFormatters.activityDuration(
                sample: sample,
                start: activityStart,
                display: element.durationDisplay
            )
        case .clockTime:
            return RunOverlayFormatters.clock(
                clockTime,
                display: element.clockDisplay
            )
        case .heartRate:
            return roundedText(sample?.heartRate)
        case .cadence:
            return roundedText(sample?.cadence)
        case .power:
            return roundedText(sample?.power)
        case .altitude:
            return OverlayMeasurementFormatter.elevation(
                meters: sample?.altitudeMeters,
                unit: element.effectiveMeasurementUnit ?? .meters
            ) ?? "—"
        case .ascent:
            return OverlayMeasurementFormatter.elevation(
                meters: sample?.ascentMeters,
                unit: element.effectiveMeasurementUnit ?? .meters
            ) ?? "—"
        case .calories:
            return roundedText(sample?.caloriesKilocalories)
        case .route, .progress, .elevationProfile:
            return ""
        }
    }

    private var metricUnit: String {
        switch element.kind {
        case .pace: element.effectiveMeasurementUnit == .miles ? "/MI" : "/KM"
        case .distance: element.effectiveMeasurementUnit == .miles ? "MI" : "KM"
        case .elapsedTime, .clockTime: ""
        case .heartRate: "BPM"
        case .cadence: "SPM"
        case .power: "W"
        case .altitude, .ascent:
            element.effectiveMeasurementUnit == .feet ? "FT" : "M"
        case .calories: "KCAL"
        case .route, .progress, .elevationProfile: ""
        }
    }

    private func roundedText(_ value: Double?) -> String {
        value.map { String(Int($0.rounded())) } ?? "—"
    }

    private func fittedClockFontSize(
        _ text: String,
        width: CGFloat,
        proposed: CGFloat
    ) -> CGFloat {
        let font = NSFont(
            descriptor: NSFont.systemFont(
                ofSize: proposed,
                weight: .bold
            ).fontDescriptor.withDesign(.rounded) ?? NSFont.systemFont(
                ofSize: proposed,
                weight: .bold
            ).fontDescriptor,
            size: proposed
        ) ?? NSFont.systemFont(ofSize: proposed, weight: .bold)
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        return proposed * min(1, max(1, width - 6) / max(measured, 1)) * 0.90
    }

    private func fittedRunningFocusFontSize(
        _ text: String,
        width: CGFloat,
        proposed: CGFloat
    ) -> CGFloat {
        let font = NSFont.systemFont(ofSize: proposed, weight: .semibold)
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        return proposed * min(1, max(1, width - 8) / max(measured, 1)) * 0.96
    }
}

private struct ElevationProfileGlyph: View {
    let profile: ElevationProfile
    let current: ActivitySample?
    let unit: OverlayMeasurementUnit
    let accent: Color
    let language: VideoTextLanguage
    let textScale: Double

    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            let plot = ElevationProfile.plotRect(in: rect, originAtTop: true)
            let ascent = OverlayMeasurementFormatter.elevation(
                meters: current?.ascentMeters,
                unit: unit
            ) ?? "—"
            let distances = profile.distanceLabels
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    guard profile.isAvailable else { return }
                    var line = Path()
                    for point in profile.points {
                        let location = profile.position(
                            for: point,
                            in: plot,
                            originAtTop: true
                        )
                        if point.startsNewSegment || line.isEmpty {
                            line.move(to: location)
                        } else {
                            line.addLine(to: location)
                        }
                    }
                    var baseline = Path()
                    baseline.move(to: CGPoint(x: plot.minX, y: plot.maxY))
                    baseline.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                    context.stroke(baseline, with: .color(.white.opacity(0.25)))
                    context.stroke(
                        line,
                        with: .color(.white.opacity(0.48)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    if let marker = profile.marker(
                        for: current,
                        in: plot,
                        originAtTop: true
                    ) {
                        context.drawLayer { layer in
                            layer.clip(to: Path(CGRect(
                                x: plot.minX, y: plot.minY,
                                width: max(0, marker.x - plot.minX),
                                height: plot.height
                            )))
                            layer.stroke(
                                line,
                                with: .color(accent),
                                style: StrokeStyle(
                                    lineWidth: 2,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                        }
                        let radius: CGFloat = 4
                        context.fill(
                            Path(ellipseIn: CGRect(
                                x: marker.x - radius, y: marker.y - radius,
                                width: radius * 2, height: radius * 2
                            )),
                            with: .color(.white)
                        )
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(RunOverlayLocalization.text("profile.ascent", videoLanguage: language))
                        .font(.system(
                            size: max(7, geometry.size.height * 0.11 * textScale),
                            weight: .medium
                        ))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Text("\(ascent) \(unit.symbol)")
                        .font(.system(
                            size: max(9, geometry.size.height * 0.20 * textScale),
                            weight: .semibold,
                            design: .rounded
                        ))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, geometry.size.width * 0.07)
                .padding(.top, geometry.size.height * 0.05)

                HStack {
                    Text(distances.start)
                    Spacer(minLength: 2)
                    Text(distances.end)
                }
                .font(.system(
                    size: max(6, geometry.size.height * 0.10 * textScale),
                    weight: .medium,
                    design: .rounded
                ))
                .lineLimit(1)
                .foregroundStyle(.white)
                .frame(
                    width: plot.width,
                    height: geometry.size.height * 0.16
                )
                .position(
                    x: plot.midX,
                    y: geometry.size.height * 0.91
                )
            }
        }
        .shadow(color: .black.opacity(0.65), radius: 2, x: 0, y: 1)
    }
}

private struct RunningProgressBar: View {
    let progress: ActivityProgress?
    let accent: Color
    let textScale: Double

    var body: some View {
        GeometryReader { geometry in
            let layout = RunningProgressBarLayout(
                in: CGRect(origin: .zero, size: geometry.size),
                progress: progress?.fraction
            )
            let labels = [
                progress?.startLabel ?? "0km",
                progress?.currentLabel ?? "— km",
                progress?.totalLabel ?? "— km"
            ]
            let proposedSize = max(
                6,
                layout.labels.height * RunningProgressBarLayout.labelHeightFraction * textScale
            )
            let descriptor = NSFont.systemFont(
                ofSize: proposedSize,
                weight: .semibold
            ).fontDescriptor.withDesign(.rounded)
            let font = descriptor.flatMap {
                NSFont(descriptor: $0, size: proposedSize)
            } ?? NSFont.systemFont(ofSize: proposedSize, weight: .semibold)
            let widestLabel = [
                labels[0], labels[2]
            ].map {
                ($0 as NSString).size(withAttributes: [.font: font]).width
            }.max() ?? 0
            let labelSize = proposedSize * min(
                1,
                max(1, layout.labels.width / 2 - 2) / max(widestLabel, 1)
            )
            let currentLabel = labels[1]
            let currentProposedSize = max(
                6,
                layout.currentLabel.height *
                    RunningProgressBarLayout.labelHeightFraction * textScale
            )
            let currentFont = NSFont.systemFont(
                ofSize: currentProposedSize,
                weight: .semibold
            )
            let proposedCurrentWidth = (currentLabel as NSString).size(
                withAttributes: [.font: currentFont]
            ).width
            let currentSize = currentProposedSize * min(
                1,
                max(1, layout.currentLabel.width - 2) /
                    max(proposedCurrentWidth, 1)
            )
            let fittedCurrentWidth = proposedCurrentWidth *
                currentSize / currentProposedSize
            ZStack {
                Canvas { context, _ in
                    guard layout.track.width > 0 else { return }
                    let trackPath = Path(
                        roundedRect: layout.track,
                        cornerRadius: layout.track.height / 2
                    )
                    context.fill(trackPath, with: .color(accent.opacity(0.30)))
                    if layout.fill.width > 0 {
                        context.clip(to: trackPath)
                        context.fill(Path(layout.fill), with: .color(accent))
                    }
                }
                HStack(spacing: 0) {
                    Text(labels[0])
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(labels[2])
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: labelSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: layout.labels.width, height: layout.labels.height)
                .position(x: layout.labels.midX, y: layout.labels.midY)

                Text(currentLabel)
                    .font(.system(
                        size: currentSize,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .position(
                        x: layout.currentLabelCenterX(
                            forTextWidth: fittedCurrentWidth
                        ),
                        y: layout.currentLabel.midY
                    )
            }
            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
        }
    }
}

private struct RouteGlyph: View {
    let coordinates: [GeoCoordinate]
    let currentCoordinate: GeoCoordinate?
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let displayCoordinates = downsampled(coordinates, maximumCount: 600)
            let points = projected(displayCoordinates, in: size)

            var path = Path()
            guard let first = points.first else {
                return
            }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(
                path,
                with: .color(accent),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )

            if let currentCoordinate,
               let current = projected([currentCoordinate], in: size, boundsFrom: displayCoordinates).first {
                let radius = max(4, size.width * 0.025)
                let marker = CGRect(
                    x: current.x - radius,
                    y: current.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(Path(ellipseIn: marker), with: .color(.white))
            }
        }
    }

    private func downsampled(
        _ coordinates: [GeoCoordinate],
        maximumCount: Int
    ) -> [GeoCoordinate] {
        guard coordinates.count > maximumCount else {
            return coordinates
        }
        let stride = max(1, coordinates.count / maximumCount)
        var result = Swift.stride(from: 0, to: coordinates.count, by: stride)
            .map { coordinates[$0] }
        if let last = coordinates.last, result.last != last {
            result.append(last)
        }
        return result
    }

    private func projected(
        _ coordinates: [GeoCoordinate],
        in size: CGSize,
        boundsFrom boundsCoordinates: [GeoCoordinate]? = nil
    ) -> [CGPoint] {
        let padding = 6.0
        let rect = CGRect(
            x: padding,
            y: padding,
            width: max(0, size.width - padding * 2),
            height: max(0, size.height - padding * 2)
        )
        return RouteProjection.points(
            for: coordinates,
            in: rect,
            using: boundsCoordinates
        )
    }
}

private struct TimelinePlaceholder: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var scrubbingTime: TimeInterval?
    let video: VideoItem

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    appModel.stepPlaybackFrame(-1)
                } label: {
                    Image(systemName: "backward.frame.fill")
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .smallIcon))
                .help(AppStrings.text("ui.timeline.previousFrame"))
                .accessibilityLabel(AppStrings.text("ui.timeline.previousFrame"))
                .disabled(appModel.player.currentItem == nil)

                Button {
                    appModel.togglePlayback()
                } label: {
                    Image(
                        systemName: appModel.isPlaying
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .frame(width: 20)
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .icon))
                .keyboardShortcut(.return, modifiers: [])
                .help(
                    AppStrings.text(
                        appModel.isPlaying
                            ? "ui.timeline.pauseHint"
                            : "ui.timeline.playHint"
                    )
                )
                .accessibilityLabel(
                    AppStrings.text(
                        appModel.isPlaying
                            ? "ui.timeline.pause"
                            : "ui.timeline.play"
                    )
                )
                .disabled(appModel.player.currentItem == nil)

                Button {
                    appModel.stepPlaybackFrame(1)
                } label: {
                    Image(systemName: "forward.frame.fill")
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .smallIcon))
                .help(AppStrings.text("ui.timeline.nextFrame"))
                .accessibilityLabel(AppStrings.text("ui.timeline.nextFrame"))
                .disabled(appModel.player.currentItem == nil)

                Text(
                    RunOverlayFormatters.duration(
                        scrubbingTime ?? appModel.playbackTime
                    )
                )
                    .font(.caption.monospacedDigit())

                Slider(
                    value: Binding(
                        get: { scrubbingTime ?? appModel.playbackTime },
                        set: {
                            scrubbingTime = $0
                            appModel.seek(to: $0)
                        }
                    ),
                    in: 0...max(video.metadata.durationSeconds, 1),
                    onEditingChanged: { isEditing in
                        if isEditing {
                            appModel.pausePlayback()
                        } else {
                            scrubbingTime = nil
                        }
                    }
                )
                .disabled(appModel.player.currentItem == nil)
                .accessibilityLabel(AppStrings.text("ui.timeline.playback"))
                .help(AppStrings.text("ui.timeline.seekHint"))

                Text(RunOverlayFormatters.duration(video.metadata.durationSeconds))
                    .font(.caption.monospacedDigit())
            }

            HStack {
                Label(
                    appModel.project.activitySource == nil
                        ? AppStrings.text("ui.match.importHint")
                        : AppStrings.format(
                            "ui.match.readyWithStatus",
                            video.activityMatch.status.displayName
                        ),
                    systemImage: "waveform.path.ecg"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    AppStrings.format(
                        "ui.match.offsetValue",
                        video.activityMatch.timeOffset
                    )
                )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(height: 92)
        .background(EditorTheme.sidebar)
    }
}

private struct EmptyEditorView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(EditorTheme.accent)
                .frame(width: 76, height: 76)
                .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 19))
            Text(AppStrings.text("ui.editor.importTitle"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(EditorTheme.text)
            Text(AppStrings.text("ui.editor.importDescription"))
                .font(.callout)
                .foregroundStyle(EditorTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EditorTheme.canvas)
    }
}

private extension Color {
    init(overlayHex hex: String) {
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
