import AppKit
import RunOverlayCore
import SwiftUI

struct ProjectSidebar: View {
    @EnvironmentObject private var appModel: AppModel
    let onShowReleaseHistory: () -> Void
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var outputControlFrames: [UUID: CGRect] = [:]
    @State private var selectionDragStart: CGPoint?
    @State private var selectionDragEnd: CGPoint?
    @State private var dragBaseSelection: Set<UUID> = []
    @State private var selectionBeforeDrag: Set<UUID>?
    @State private var selectionAnchorID: UUID?
    @State private var isShowingClearVideosConfirmation = false
    @State private var isShowingClearActivityConfirmation = false
    @State private var isShowingCaptureTimeEditor = false
    @State private var captureTimeVideoID: UUID?
    @State private var captureTimeInput = ""
    @FocusState private var isVideoListFocused: Bool

    private let selectionSpace = "videoSelectionArea"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EditorTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                Text(AppStrings.text("ui.sidebar.mediaLibrary"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EditorTheme.text)
                Spacer()
                Text("\(appModel.project.videos.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(EditorTheme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(EditorTheme.separator)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(AppStrings.text("ui.activity.section"))
                    Spacer()
                    Button {
                        isShowingClearActivityConfirmation = true
                    } label: {
                        Label(
                            AppStrings.text("ui.activity.clear"),
                            systemImage: "trash"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(EditorActionButtonStyle(tone: .destructive, size: .compact))
                    .disabled(!appModel.canClearActivity)
                    .help(AppStrings.text("ui.activity.clear"))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(EditorTheme.muted)
                Button {
                    appModel.presentActivityImportPanel()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "figure.run")
                            .foregroundStyle(
                                appModel.project.activitySource == nil
                                    ? Color.secondary
                                    : Color.green
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                appModel.project.activitySource?.fileName ??
                                    AppStrings.text("ui.activity.importFitGpx")
                            )
                            .lineLimit(1)
                            if let source = appModel.project.activitySource {
                                Text(
                                    appModel.isActivityResourceMissing
                                        ? AppStrings.text("ui.activity.sourceMissing")
                                        : AppStrings.format(
                                            "ui.activity.summary",
                                            source.sampleCount,
                                            source.availableChannels.count
                                        )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    appModel.isActivityResourceMissing ? .red : .secondary
                                )
                                .help(
                                    appModel.isActivityResourceMissing
                                        ? appModel.activitySourceStatusMessage ??
                                            AppStrings.text("ui.activity.sourceMissingHelp")
                                        : AppStrings.text("ui.activity.section")
                                )
                            } else {
                                Text(AppStrings.text("ui.activity.chooseRun"))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer(minLength: 0)
                        if appModel.isImportingActivity {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                .disabled(appModel.exportBatchHasStarted)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 18)

            HStack {
                Text(AppStrings.format(
                    "ui.video.section",
                    appModel.project.videos.count
                ))
                Spacer(minLength: 0)
                if let selection = appModel.exportVideoSelection {
                    Text(AppStrings.format(
                        "ui.video.selectedForExport",
                        selection.count
                    ))
                    .font(.caption)
                }
                Button {
                    isShowingClearVideosConfirmation = true
                } label: {
                    Label(
                        AppStrings.text("ui.video.clearAll"),
                        systemImage: "trash"
                    )
                    .font(.caption)
                }
                .buttonStyle(EditorActionButtonStyle(tone: .destructive, size: .compact))
                .disabled(!appModel.canClearVideos)
                .help(AppStrings.text("ui.video.clearAll"))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(EditorTheme.muted)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "aspectratio")
                        .accessibilityHidden(true)
                    Text(AppStrings.text("ui.video.batchAspectRatio"))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(EditorTheme.muted)

                EditorChoiceTabs(
                    options: ExportAspectRatio.allCases,
                    selection: appModel.project.exportSettings.aspectRatio,
                    columns: 3,
                    title: { ratio in
                        switch ratio {
                        case .source: AppStrings.text("ui.workspace.aspectRatio.sourceShort")
                        case .landscape16x9: "16:9"
                        case .portrait9x16: "9:16"
                        case .landscape4x3: "4:3"
                        case .portrait3x4: "3:4"
                        case .square: "1:1"
                        case .portrait4x5: "4:5"
                        }
                    },
                    onSelect: { appModel.setExportAspectRatio($0) }
                )
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .disabled(appModel.exportBatchHasStarted)

            GeometryReader { viewport in
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(appModel.project.videos) { video in
                                videoListRow(video)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: viewport.size.height, alignment: .top)
                        .contentShape(Rectangle())
                    }
                    .coordinateSpace(name: selectionSpace)
                    .onPreferenceChange(VideoRowFramesKey.self) { frames in
                        rowFrames = frames
                    }
                    .onPreferenceChange(VideoOutputControlFramesKey.self) { frames in
                        outputControlFrames = frames
                    }
                    .overlay {
                        if let selectionDragStart, let selectionDragEnd {
                            Rectangle()
                                .fill(EditorTheme.accent.opacity(0.13))
                                .overlay {
                                    Rectangle()
                                        .strokeBorder(
                                            EditorTheme.accent.opacity(0.75),
                                            lineWidth: 1
                                        )
                                }
                                .frame(
                                    width: max(1, abs(selectionDragEnd.x - selectionDragStart.x)),
                                    height: max(1, abs(selectionDragEnd.y - selectionDragStart.y))
                                )
                                .position(
                                    x: (selectionDragStart.x + selectionDragEnd.x) / 2,
                                    y: (selectionDragStart.y + selectionDragEnd.y) / 2
                                )
                                .allowsHitTesting(false)
                        }
                    }
                    // 框选与行内输出设置同时响应，避免拖拽手势吞掉旋转和画幅按钮。
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(selectionSpace))
                            .onChanged(updateDragSelection)
                            .onEnded(endDragSelection)
                    )
                    .focusable()
                    .focused($isVideoListFocused)
                    .onMoveCommand { direction in
                        guard isVideoListFocused, appModel.canBrowseVideosDuringExport else {
                            return
                        }
                        let step: Int
                        switch direction {
                        case .up: step = -1
                        case .down: step = 1
                        default: return
                        }
                        guard let nextID = VideoListNavigation().adjacentVideoID(
                            in: appModel.project.videos,
                            currentID: appModel.selectedVideoID,
                            direction: step
                        ) else {
                            return
                        }
                        appModel.setExportVideoSelection([nextID])
                        selectionAnchorID = nextID
                        if let nextFrame = rowFrames[nextID],
                           nextFrame.minY >= 0,
                           nextFrame.maxY <= viewport.size.height {
                            return
                        }
                        withAnimation(.easeOut(duration: 0.16)) {
                            scrollProxy.scrollTo(
                                nextID,
                                anchor: step > 0 ? .bottom : .top
                            )
                        }
                    }
                }
            }
            .background(EditorTheme.sidebar)
            .onDeleteCommand {
                if !appModel.exportBatchHasStarted && appModel.canDeleteSelectedVideo {
                    appModel.removeSelectedVideo()
                }
            }

            Rectangle()
                .fill(EditorTheme.separator)
                .frame(height: 1)

            HStack(spacing: 10) {
                Button {
                    appModel.presentVideoImportPanel()
                } label: {
                    Label(AppStrings.text("ui.import"), systemImage: "plus")
                }
                .buttonStyle(EditorActionButtonStyle(tone: .primary, size: .compact))
                .controlSize(.regular)
                .disabled(appModel.exportBatchHasStarted)

                Spacer()

                if appModel.isImportingVideos {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    appModel.removeSelectedVideo()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .icon))
                .disabled(
                    !appModel.canDeleteSelectedVideo ||
                        appModel.exportBatchHasStarted
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(EditorTheme.sidebar)

            Button(action: onShowReleaseHistory) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(EditorTheme.accent)
                    Text(AppStrings.text("ui.release.title"))
                    Spacer()
                    Text(AppStrings.text("ui.release.view"))
                        .foregroundStyle(EditorTheme.muted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(EditorTheme.muted)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EditorTheme.text)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(EditorTheme.surface.opacity(0.55), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .background(EditorTheme.sidebar)
        }
        .background(EditorTheme.sidebar)
        .confirmationDialog(
            AppStrings.text("ui.video.clearAllConfirmation"),
            isPresented: $isShowingClearVideosConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.text("ui.video.clearAll"), role: .destructive) {
                appModel.clearVideos()
                selectionAnchorID = nil
                rowFrames.removeAll()
                outputControlFrames.removeAll()
            }
            Button(AppStrings.text("ui.common.cancel"), role: .cancel) {}
        } message: {
            Text(AppStrings.text("ui.video.clearAllExplanation"))
        }
        .confirmationDialog(
            AppStrings.text("ui.activity.clearConfirmation"),
            isPresented: $isShowingClearActivityConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.text("ui.activity.clear"), role: .destructive) {
                appModel.clearActivity()
            }
            Button(AppStrings.text("ui.common.cancel"), role: .cancel) {}
        } message: {
            Text(AppStrings.text("ui.activity.clearExplanation"))
        }
        .sheet(isPresented: $isShowingCaptureTimeEditor) {
            captureTimeEditor
        }
    }

    private func videoListRow(_ video: VideoItem) -> some View {
        let isSelected = appModel.exportVideoSelection?.contains(video.id) == true
        return VStack(alignment: .leading, spacing: 4) {
            VideoRow(
                video: video,
                isMissing: appModel.missingResourceVideoIDs.contains(video.id),
                isTimeResourceMissing: appModel.missingVideoTimeResourceIDs.contains(video.id)
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                guard appModel.canBrowseVideosDuringExport else { return }
                appModel.setExportVideoSelection([video.id])
                selectionAnchorID = video.id
            }
            if appModel.selectedVideoID == video.id,
               appModel.exportVideoSelection == nil || appModel.exportVideoSelection == [video.id] {
                videoOutputControls(for: video)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 9)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: VideoOutputControlFramesKey.self,
                                value: [
                                    video.id: geometry.frame(in: .named(selectionSpace))
                                ]
                            )
                        }
                    }
            }
        }
        .id(video.id)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(
                    isSelected
                        ? EditorTheme.accent.opacity(0.18)
                        : EditorTheme.surface.opacity(0.68)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    isSelected ? EditorTheme.accent.opacity(0.65) : Color.clear,
                    lineWidth: 1
                )
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: VideoRowFramesKey.self,
                    value: [video.id: geometry.frame(in: .named(selectionSpace))]
                )
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                appModel.setExportVideoSelection([video.id])
                appModel.removeSelectedVideo()
            } label: {
                Label(AppStrings.text("ui.video.delete"), systemImage: "trash")
            }
            .disabled(appModel.exportBatchHasStarted)
        }
    }

    private func videoOutputControls(for video: VideoItem) -> some View {
        let plan = appModel.outputPlan(for: video)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(AppStrings.text("ui.video.rotation"))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(video.rotation.rawValue)°")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(EditorTheme.muted)
            }
            HStack(spacing: 6) {
                Button {
                    appModel.rotateVideo(video.id, clockwise: false)
                } label: {
                    Label(
                        AppStrings.text("ui.video.rotateLeft"),
                        systemImage: "rotate.left"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))

                Button {
                    appModel.rotateVideo(video.id, clockwise: true)
                } label: {
                    Label(
                        AppStrings.text("ui.video.rotateRight"),
                        systemImage: "rotate.right"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(EditorTheme.text)
            if plan.needsAttention {
                Label(
                    appModel.outputWarningDescription(for: plan),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption2)
                .foregroundStyle(.yellow)
                .fixedSize(horizontal: false, vertical: true)
            }
            matchTimeControls(for: video)
        }
    }

    private func matchTimeControls(for video: VideoItem) -> some View {
        let diagnostic = VideoMatchDiagnostic(
            video: video,
            activityRange: appModel.project.activitySource?.timeRange
        )
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(AppStrings.text("ui.video.captureTime"))
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    captureTimeVideoID = video.id
                    captureTimeInput = video.effectiveCapturedAt.map {
                        VideoCaptureTimeFormatter.format($0)
                    } ?? ""
                    isShowingCaptureTimeEditor = true
                } label: {
                    Label(AppStrings.text("ui.video.captureEdit"), systemImage: "pencil")
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
            }
            if let recorded = diagnostic.recordedStart {
                Text(
                    "\(AppStrings.text("ui.video.captureSource.\(diagnostic.captureSource.rawValue)")) · \(VideoCaptureTimeFormatter.format(recorded))"
                )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(EditorTheme.muted)
                if video.activityMatch.timeOffset != 0, let aligned = diagnostic.alignedStart {
                    Text(
                        "\(AppStrings.text("ui.video.alignedTime"))：\(VideoCaptureTimeFormatter.format(aligned))"
                    )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(EditorTheme.muted)
                }
            } else {
                Text(AppStrings.text("ui.video.captureMissing"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if let activityRange = appModel.project.activitySource?.timeRange {
                Text(
                    "\(AppStrings.text("ui.video.activityRange"))：\(VideoCaptureTimeFormatter.format(activityRange.start)) → \(VideoCaptureTimeFormatter.format(activityRange.end))"
                )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(EditorTheme.muted)
                if let difference = diagnostic.secondsFromActivityStart {
                    Text("\(AppStrings.text("ui.video.activityDifference"))：\(signedDuration(difference))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(
                            video.activityMatch.status == .complete
                                ? EditorTheme.muted : Color.orange
                        )
                    if diagnostic.secondsBeforeActivity > 0 {
                        Text("\(AppStrings.text("ui.video.uncoveredBefore"))：\(RunOverlayFormatters.duration(diagnostic.secondsBeforeActivity))")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if diagnostic.secondsAfterActivity > 0 {
                        Text("\(AppStrings.text("ui.video.uncoveredAfter"))：\(RunOverlayFormatters.duration(diagnostic.secondsAfterActivity))")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Text(AppStrings.text("ui.video.noActivity"))
                    .font(.caption2)
                    .foregroundStyle(EditorTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captureTimeEditor: some View {
        let video = captureTimeVideoID.flatMap { id in
            appModel.project.videos.first(where: { $0.id == id })
        }
        let parsed = VideoCaptureTimeFormatter.parse(captureTimeInput)
        return VStack(alignment: .leading, spacing: 14) {
            Text(AppStrings.text("ui.video.captureEdit"))
                .font(.title3.weight(.semibold))
            Text(video?.fileName ?? "")
                .font(.caption)
                .foregroundStyle(EditorTheme.muted)
            Text(AppStrings.text("ui.video.captureInputHint"))
                .font(.caption)
                .foregroundStyle(EditorTheme.muted)
            TextField("yyyy-MM-dd HH:mm:ss", text: $captureTimeInput)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospacedDigit())
            if !captureTimeInput.isEmpty, parsed == nil {
                Text(AppStrings.text("ui.video.invalidCaptureTime"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let video, video.activityMatch.timeOffset != 0 {
                Text(AppStrings.text("ui.video.captureOffsetHint"))
                    .font(.caption)
                    .foregroundStyle(EditorTheme.muted)
            }
            HStack {
                if video?.manualCapturedAt != nil {
                    Button(AppStrings.text("ui.video.captureReset")) {
                        if let video { appModel.setVideoCapturedAt(nil, for: video.id) }
                        isShowingCaptureTimeEditor = false
                    }
                    .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                }
                Spacer()
                Button(AppStrings.text("ui.common.cancel")) {
                    isShowingCaptureTimeEditor = false
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                Button(AppStrings.text("ui.video.captureSave")) {
                    guard let video, let parsed else { return }
                    appModel.setVideoCapturedAt(parsed, for: video.id)
                    isShowingCaptureTimeEditor = false
                }
                .buttonStyle(EditorActionButtonStyle(tone: .primary, size: .compact))
                .disabled(video == nil || parsed == nil || appModel.exportBatchHasStarted)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(EditorTheme.sidebar)
    }

    private func signedDuration(_ seconds: TimeInterval) -> String {
        let prefix = seconds < 0 ? "−" : "+"
        return prefix + RunOverlayFormatters.duration(abs(seconds))
    }

    private func updateDragSelection(_ value: DragGesture.Value) {
        guard appModel.canBrowseVideosDuringExport, !rowFrames.isEmpty else {
            return
        }
        guard !outputControlFrames.values.contains(where: {
            $0.contains(value.startLocation)
        }) else {
            return
        }
        guard hypot(value.translation.width, value.translation.height) >= 6 else {
            return
        }
        if selectionDragStart == nil {
            selectionDragStart = value.startLocation
            selectionBeforeDrag = appModel.exportVideoSelection
            dragBaseSelection = NSEvent.modifierFlags.contains(.command)
                ? appModel.exportVideoSelection ?? []
                : []
        }
        selectionDragEnd = value.location
        let selection = CGRect(
            x: min(value.startLocation.x, value.location.x),
            y: min(value.startLocation.y, value.location.y),
            width: max(1, abs(value.location.x - value.startLocation.x)),
            height: max(1, abs(value.location.y - value.startLocation.y))
        )
        let draggedIDs = ExportVideoSelection().videoIDs(
            intersecting: selection,
            rowFrames: rowFrames
        )
        appModel.setExportVideoSelection(
            dragBaseSelection.union(draggedIDs),
            previewIfSingle: false,
            recordsHistory: false
        )
    }

    private func endDragSelection(_ value: DragGesture.Value) {
        defer {
            selectionDragStart = nil
            selectionDragEnd = nil
            dragBaseSelection = []
            selectionBeforeDrag = nil
        }
        guard appModel.canBrowseVideosDuringExport else { return }
        isVideoListFocused = true
        guard !outputControlFrames.values.contains(where: {
            $0.contains(value.startLocation)
        }) else {
            return
        }
        if selectionDragStart != nil {
            updateDragSelection(value)
            appModel.recordExportSelectionChange(from: selectionBeforeDrag)
            return
        }
        guard let videoID = rowFrames.first(where: {
            $0.value.contains(value.startLocation)
        })?.key else {
            if !NSEvent.modifierFlags.contains(.command) {
                appModel.setExportVideoSelection([], previewIfSingle: false)
            }
            return
        }
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift),
           let anchorID = selectionAnchorID ?? appModel.selectedVideoID,
           let first = appModel.project.videos.firstIndex(where: { $0.id == anchorID }),
           let last = appModel.project.videos.firstIndex(where: { $0.id == videoID }) {
            let range = min(first, last)...max(first, last)
            let selected = Set(appModel.project.videos[range].map(\.id))
            let existing: Set<UUID> = flags.contains(.command)
                ? appModel.exportVideoSelection ?? []
                : []
            appModel.setExportVideoSelection(
                existing.union(selected),
                previewIfSingle: false
            )
        } else if flags.contains(.command) {
            var selected = appModel.exportVideoSelection ?? []
            if selected.contains(videoID) {
                selected.remove(videoID)
            } else {
                selected.insert(videoID)
            }
            appModel.setExportVideoSelection(selected, previewIfSingle: false)
            selectionAnchorID = videoID
        } else {
            appModel.setExportVideoSelection([videoID])
            selectionAnchorID = videoID
        }
    }
}

private struct VideoRowFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }

    static func reduce(
        value: inout [UUID: CGRect],
        nextValue: () -> [UUID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct VideoOutputControlFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }

    static func reduce(
        value: inout [UUID: CGRect],
        nextValue: () -> [UUID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct VideoRow: View {
    @EnvironmentObject private var appModel: AppModel
    let video: VideoItem
    let isMissing: Bool
    let isTimeResourceMissing: Bool

    var body: some View {
        let plan = appModel.outputPlan(for: video)
        HStack(spacing: 10) {
            statusIcon
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 32)
                .contentShape(Rectangle())
                .help(statusHelp)
                .accessibilityLabel(statusHelp)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if let thumbnail = appModel.videoThumbnails[video.id] {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "film")
                            .frame(width: 64, height: 42)
                            .foregroundStyle(.tertiary)
                            .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(video.fileName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            matchedDataBadge
                            if plan.needsAttention {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                    .help(
                                        AppStrings.format(
                                            "ui.video.outputWarningHelp",
                                            video.metadata.dimensions.displayText,
                                            plan.outputDimensions.displayText,
                                            appModel.outputWarningDescription(for: plan)
                                        )
                                    )
                                    .accessibilityLabel(AppStrings.text("ui.video.outputWarning"))
                            }
                        }

                        Text(
                            "\(RunOverlayFormatters.duration(video.metadata.durationSeconds)) · \(video.metadata.dimensions.displayText)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        let diagnostic = VideoMatchDiagnostic(
                            video: video,
                            activityRange: appModel.project.activitySource?.timeRange
                        )
                        if let recorded = diagnostic.recordedStart {
                            let source = AppStrings.text(
                                "ui.video.captureSource.\(diagnostic.captureSource.rawValue)"
                            )
                            let difference = diagnostic.secondsFromActivityStart.map {
                                " · \(signedDuration($0))"
                            } ?? ""
                            Text("\(source) · \(VideoCaptureTimeFormatter.format(recorded))\(difference)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .help("\(source) · \(VideoCaptureTimeFormatter.format(recorded))\(difference)")
                        }
                        if let timeResource = video.timeResource {
                            Text(
                                isTimeResourceMissing
                                    ? AppStrings.format(
                                        "ui.video.missingTime",
                                        timeResource.fileName
                                    )
                                    : AppStrings.format(
                                        "ui.video.timeResourceValue",
                                        timeResource.fileName
                                    )
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                isTimeResourceMissing
                                    ? Color.red
                                    : Color.secondary
                            )
                            .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var matchedDataBadge: some View {
        if !isMissing,
           !appModel.isActivityResourceMissing,
           appModel.project.activitySource != nil {
            switch video.activityMatch.status {
            case .complete:
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .fixedSize()
                    .help(statusHelp)
                    .accessibilityLabel(statusHelp)
            case .partial:
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                    .fixedSize()
                    .help(statusHelp)
                    .accessibilityLabel(statusHelp)
            case .pending, .unmatched:
                EmptyView()
            }
        }
    }

    private var statusHelp: String {
        if isMissing {
            return AppStrings.text("ui.video.statusHelp.missing")
        }
        if appModel.isActivityResourceMissing {
            return AppStrings.text("ui.video.statusHelp.activityMissing")
        }
        let summary: String = switch video.activityMatch.status {
        case .pending:
            AppStrings.text("ui.video.statusHelp.pending")
        case .complete:
            AppStrings.text("ui.video.statusHelp.complete")
        case .partial:
            AppStrings.text("ui.video.statusHelp.partial")
        case .unmatched:
            AppStrings.text("ui.video.statusHelp.unmatched")
        }
        let diagnostic = VideoMatchDiagnostic(
            video: video,
            activityRange: appModel.project.activitySource?.timeRange
        )
        guard let difference = diagnostic.secondsFromActivityStart,
              let recorded = diagnostic.recordedStart else {
            return summary
        }
        let time = VideoCaptureTimeFormatter.format(recorded)
        let gap = signedDuration(difference)
        return "\(summary)\n\(AppStrings.text("ui.video.captureSource.\(diagnostic.captureSource.rawValue)"))：\(time)\n\(AppStrings.text("ui.video.activityDifference"))：\(gap)"
    }

    private func signedDuration(_ seconds: TimeInterval) -> String {
        let prefix = seconds < 0 ? "−" : "+"
        return prefix + RunOverlayFormatters.duration(abs(seconds))
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isMissing {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else {
            switch video.activityMatch.status {
            case .pending:
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(video.timeResource == nil ? .green : .mint)
            case .partial:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            case .unmatched:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}
