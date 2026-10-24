import AppKit
import AVFoundation
import AVKit
import RunOverlayCore
import SwiftUI

/// 使用 AppKit 原生播放器，避免 SwiftUI VideoPlayer 在独立 macOS 窗口初始化时崩溃。
private struct SmartEditPlaybackView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player = nil
    }
}

struct SmartEditWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    let onClose: () -> Void
    let onToggleFullscreen: () -> Void
    @State private var sources: [SmartEditMediaSource] = []
    @State private var drafts: [SmartEditDraft] = []
    @State private var selectedDraftID: UUID?
    @State private var selectedCutClipID: UUID?
    @State private var isAnalyzing = false
    @State private var isExporting = false
    @State private var analysisProgress = 0.0
    @State private var exportProgress = 0.0
    @State private var activeAnalysisFileName: String?
    @State private var analysisMessage: String?
    @State private var errorMessage: String?
    @State private var analysisIsComplete = false
    @State private var analysisFailures: [String] = []
    @State private var draftName = ""
    @State private var activityTimeOffset = 0.0
    @State private var speechLocaleIdentifier = "zh-CN"
    @State private var targetAspectRatio: ExportAspectRatio
    @State private var targetResolution: Int
    @State private var timelineEditDraft: SmartEditDraft?
    @State private var analysisTask: Task<Void, Never>?
    @State private var exportTask: Task<Void, Never>?
    @State private var exportedURL: URL?
    @State private var previewPlayer = AVPlayer()
    @State private var previewSourceID: UUID?
    @State private var previewProjectVideoID: UUID?
    @State private var isWindowVisible = true
    @State private var customExportDirectoryURL: URL?
    @State private var isMaterialPanelExpanded = true
    @State private var isSettingsPanelExpanded = true
    @State private var previewHeight: CGFloat = 330
    @State private var previewAvailableHeight: CGFloat = 620
    @GestureState private var previewResizeTranslation: CGFloat = 0
    @Binding private var backgroundExportQueue: SmartEditBackgroundExportQueue?

    private let store = SmartEditDraftStore()
    private enum ExportDirectoryPreference {
        static let bookmark = "smartEdit.exportDirectoryBookmark"
        static let path = "smartEdit.exportDirectoryPath"
    }

    init(
        initialAspectRatio: ExportAspectRatio = .landscape16x9,
        initialResolution: Int = 1_080,
        backgroundExportQueue: Binding<SmartEditBackgroundExportQueue?> = .constant(nil),
        onClose: @escaping () -> Void,
        onToggleFullscreen: @escaping () -> Void
    ) {
        _targetAspectRatio = State(initialValue: initialAspectRatio)
        _targetResolution = State(initialValue: initialResolution)
        _backgroundExportQueue = backgroundExportQueue
        self.onClose = onClose
        self.onToggleFullscreen = onToggleFullscreen
    }

    private var selectedDraft: SmartEditDraft? {
        timelineEditDraft ?? drafts.first { $0.id == selectedDraftID }
    }

    private var projectVideos: [VideoItem] {
        appModel.project.videos
    }

    private var selectedExportDirectoryURL: URL? {
        customExportDirectoryURL ?? appModel.defaultSmartEditExportDirectoryURL
    }

    private var visiblePreviewHeight: CGFloat {
        min(
            max(190, previewHeight + previewResizeTranslation),
            max(220, previewAvailableHeight - 180)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            EditorTheme.separator.frame(height: 1)

            HStack(spacing: 0) {
                if isMaterialPanelExpanded {
                    materialPanel
                        .frame(width: 310)
                    EditorTheme.separator.frame(width: 1)
                }
                timelinePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if isSettingsPanelExpanded {
                    EditorTheme.separator.frame(width: 1)
                    settingsPanel
                        .frame(width: 280)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            EditorTheme.separator.frame(height: 1)
            footer
        }
        .background(EditorTheme.canvas)
        .preferredColorScheme(.dark)
        .onAppear {
            isWindowVisible = true
            restoreExportDirectory()
            loadDrafts()
        }
        .onChange(of: appModel.project.id) { _, _ in
            analysisTask?.cancel()
            resetCurrentProjectMaterial()
        }
        .onChange(of: projectVideos) { previous, current in
            let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
            let sourceIDsBefore = sources.map(\.id)
            sources.removeAll { source in
                guard let id = source.originalVideoID,
                      let video = currentByID[id],
                      let oldVideo = previousByID[id] else { return true }
                return appModel.resolvedVideoURLForSmartEdit(video) !=
                    appModel.resolvedVideoURLForSmartEdit(oldVideo) ||
                    video.effectiveCapturedAt != oldVideo.effectiveCapturedAt ||
                    video.activityMatch.timeOffset != oldVideo.activityMatch.timeOffset
            }
            if sources.map(\.id) != sourceIDsBefore {
                analysisIsComplete = false
                analysisMessage = nil
            }
            if let previewSourceID,
               selectedDraft == nil,
               !sources.contains(where: { $0.id == previewSourceID }) {
                previewPlayer.pause()
                previewPlayer.replaceCurrentItem(with: nil)
                self.previewSourceID = nil
            }
            if let previewProjectVideoID,
               currentByID[previewProjectVideoID] == nil {
                previewPlayer.pause()
                previewPlayer.replaceCurrentItem(with: nil)
                self.previewProjectVideoID = nil
            } else if let previewProjectVideoID,
                      let oldVideo = previousByID[previewProjectVideoID],
                      let newVideo = currentByID[previewProjectVideoID],
                      appModel.resolvedVideoURLForSmartEdit(oldVideo) !=
                        appModel.resolvedVideoURLForSmartEdit(newVideo) {
                previewPlayer.pause()
                previewPlayer.replaceCurrentItem(with: nil)
                playProjectVideo(newVideo, autoplay: false)
            }
            if previewPlayer.currentItem == nil,
               previewSourceID == nil,
               selectedDraft == nil,
               let video = current.first {
                playProjectVideo(video, autoplay: false)
            }
        }
        .onDisappear {
            isWindowVisible = false
            let exportsInBackground = isExporting &&
                backgroundExportQueue?.isComplete == false
            if !exportsInBackground {
                analysisTask?.cancel()
            }
            previewPlayer.pause()
            if !exportsInBackground && !isExporting && !isAnalyzing {
                stopSourceAccess()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Button {
                isMaterialPanelExpanded.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(
                        isMaterialPanelExpanded ? EditorTheme.accent : EditorTheme.muted
                    )
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(EditorActionButtonStyle(tone: .quiet, size: .smallIcon))
            .help(AppStrings.text(
                isMaterialPanelExpanded
                    ? "smartEdit.hideMaterialPanel"
                    : "smartEdit.showMaterialPanel"
            ))

            HStack(spacing: 13) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(EditorTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppStrings.text("smartEdit.title"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(EditorTheme.text)
                    Text(AppStrings.text("smartEdit.subtitle"))
                        .font(.system(size: 12))
                        .foregroundStyle(EditorTheme.muted)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onToggleFullscreen)

            HStack(spacing: 7) {
                Circle()
                    .fill(EditorTheme.accent)
                    .frame(width: 7, height: 7)
                Text(AppStrings.text("smartEdit.localOnly"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EditorTheme.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(EditorTheme.accent.opacity(0.1), in: Capsule())

            Button(AppStrings.text("smartEdit.close"), action: onClose)
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))

            Button {
                isSettingsPanelExpanded.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .foregroundStyle(
                        isSettingsPanelExpanded ? EditorTheme.accent : EditorTheme.muted
                    )
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(EditorActionButtonStyle(tone: .quiet, size: .smallIcon))
            .help(AppStrings.text(
                isSettingsPanelExpanded
                    ? "smartEdit.hideSettingsPanel"
                    : "smartEdit.showSettingsPanel"
            ))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(EditorTheme.sidebar)
    }

    private var materialPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelTitle(
                AppStrings.text("smartEdit.materials"),
                detail: AppStrings.format("smartEdit.materialCount", projectVideos.count)
            )

            Text(AppStrings.text("smartEdit.projectMaterialsHint"))
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !appModel.missingResourceVideoIDs.isDisjoint(
                with: Set(projectVideos.map(\.id))
            ) {
                Button {
                    appModel.presentRelinkMissingResourcesPanel()
                } label: {
                    Label(
                        AppStrings.text("ui.project.relink"),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline))
                .disabled(isAnalyzing || isExporting)
            }

            if projectVideos.isEmpty {
                VStack(spacing: 11) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(EditorTheme.muted)
                    Text(AppStrings.text("smartEdit.emptyMaterials"))
                        .font(.system(size: 12))
                        .foregroundStyle(EditorTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(projectVideos) { video in
                            materialRow(video)
                        }
                    }
                }
            }

            if !drafts.isEmpty {
                Rectangle().fill(EditorTheme.separator).frame(height: 1)
                panelTitle(AppStrings.text("smartEdit.savedDrafts"))
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(drafts) { draft in
                            Button {
                                previewPlayer.pause()
                                previewPlayer.replaceCurrentItem(with: nil)
                                selectedDraftID = draft.id
                                timelineEditDraft = draft
                                targetAspectRatio = draft.aspectRatio
                                targetResolution = draft.maximumHeight
                                speechLocaleIdentifier = draft.speechLocaleIdentifier
                                activityTimeOffset = draft.activityTimeOffset
                                previewSourceID = draft.sources.first?.id
                                previewProjectVideoID = nil
                                if let source = draft.sources.first {
                                    playSource(source)
                                }
                                exportedURL = nil
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "timeline.selection")
                                        .foregroundStyle(
                                            selectedDraftID == draft.id
                                                ? EditorTheme.accent : EditorTheme.muted
                                        )
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(draft.name)
                                            .lineLimit(1)
                                            .foregroundStyle(EditorTheme.text)
                                        Text(
                                            AppStrings.format(
                                                "smartEdit.draftSummary",
                                                draft.sources.count,
                                                durationLabel(draft.durationSeconds)
                                            )
                                        )
                                        .font(.system(size: 10))
                                        .foregroundStyle(EditorTheme.muted)
                                    }
                                    Spacer(minLength: 0)
                                    if selectedDraftID == draft.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(EditorTheme.accent)
                                    }
                                }
                                .font(.system(size: 12, weight: .medium))
                                .padding(10)
                                .background(
                                    selectedDraftID == draft.id
                                        ? EditorTheme.raised : EditorTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 9)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(16)
        .background(EditorTheme.sidebar)
    }

    private var timelinePanel: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            if let selectedDraft {
                draftTimeline(selectedDraft)
            } else if !sources.isEmpty {
                analysisResultTimeline
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if !projectVideos.isEmpty {
                        previewPanel
                            .padding(.bottom, 12)
                    }
                    Text(AppStrings.text("smartEdit.workspaceTitle"))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(EditorTheme.text)
                    Text(AppStrings.text("smartEdit.workspaceDescription"))
                        .font(.system(size: 13))
                        .foregroundStyle(EditorTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        featureNote(
                            symbol: "waveform",
                            title: AppStrings.text("smartEdit.voiceFirstTitle"),
                            detail: AppStrings.text("smartEdit.voiceFirstDetail")
                        )
                        featureNote(
                            symbol: "scissors",
                            title: AppStrings.text("smartEdit.localSceneTitle"),
                            detail: AppStrings.text("smartEdit.localSceneDetail")
                        )
                    }
                    .padding(.top, 12)

                    Rectangle()
                        .fill(EditorTheme.separator)
                        .frame(height: 1)
                        .padding(.vertical, 8)
                    Text(AppStrings.text("smartEdit.noFixedDuration"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(EditorTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(EditorTheme.canvas)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { previewAvailableHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, height in
                        previewAvailableHeight = height
                    }
            }
        }
    }

    private var analysisResultTimeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            previewPanel
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.text("smartEdit.analysisResult"))
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(EditorTheme.text)
                    Text(AppStrings.format("smartEdit.detectedSources", sources.count))
                        .font(.system(size: 12))
                        .foregroundStyle(EditorTheme.muted)
                }
                Spacer()
                Text(AppStrings.text(
                    isAnalyzing ? "smartEdit.analysisInProgress"
                        : (analysisIsComplete
                            ? "smartEdit.analysisReadyToReview"
                            : "smartEdit.analysisIncomplete")
                ))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        isAnalyzing || analysisIsComplete
                            ? EditorTheme.accent : .orange
                    )
            }

            if analysisIsComplete {
                analysisPlan
            } else if !isAnalyzing {
                Text(AppStrings.text("smartEdit.analysisIncompleteHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            trackHeader(
                AppStrings.text("smartEdit.voiceTrack"),
                detail: AppStrings.text("smartEdit.voiceTrackHint"),
                symbol: "waveform"
            )
            ForEach(sources) { source in
                if source.hasAudio {
                    sourceTrack(source, isAudio: true)
                } else {
                    trackBlock(
                        title: source.fileName,
                        detail: AppStrings.text("smartEdit.noAudioInSource"),
                        icon: "speaker.slash",
                        tint: EditorTheme.raised,
                        locked: false
                    )
                }
            }

            trackHeader(
                AppStrings.text("smartEdit.pictureTrack"),
                detail: AppStrings.text("smartEdit.pictureTrackHint"),
                symbol: "film"
            )
            ForEach(sources) { source in
                sourceTrack(source, isAudio: false)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var analysisPlan: some View {
        let summary = SmartEditAnalysisSummary(sources: sources)
        return VStack(alignment: .leading, spacing: 11) {
                Label(
                    AppStrings.text("smartEdit.analysisPlanTitle"),
                    systemImage: "text.badge.checkmark"
                )
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(EditorTheme.accent)

                Text(AppStrings.format(
                    "smartEdit.analysisPlanSummary",
                    summary.sources.count,
                    summary.proposedClipCount,
                    durationLabel(summary.totalDurationSeconds),
                    durationLabel(summary.outputDurationSeconds),
                    durationLabel(summary.removedDurationSeconds)
                ))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EditorTheme.text)

                ForEach(Array(summary.sources.enumerated()), id: \.offset) { _, source in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.fileName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(EditorTheme.text)
                            .lineLimit(1)
                        Text(AppStrings.format(
                            "smartEdit.analysisSourcePlan",
                            durationLabel(source.durationSeconds),
                            source.candidateBoundaryCount,
                            source.proposedClipCount,
                            source.speechCueCount
                        ))
                        .font(.system(size: 10))
                        .foregroundStyle(EditorTheme.muted)
                        Text(analysisCutDescription(for: source))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(EditorTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(AppStrings.format(
                            "smartEdit.analysisSourceTrim",
                            durationLabel(source.keptDurationSeconds),
                            durationLabel(source.removedDurationSeconds)
                        ))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(EditorTheme.accent)
                        Text(analysisSpeechDescription(for: source))
                            .font(.system(size: 10))
                            .foregroundStyle(EditorTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(EditorTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                }

                Text(AppStrings.text("smartEdit.analysisPlanRules"))
                    .font(.system(size: 11))
                    .foregroundStyle(EditorTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AppStrings.text("smartEdit.analysisPlanLimit"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(EditorTheme.highlight)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AppStrings.text("smartEdit.analysisPlanConfirmation"))
                    .font(.system(size: 11))
                    .foregroundStyle(EditorTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 11))
    }

    private func analysisSpeechDescription(
        for source: SmartEditAnalysisSummary.Source
    ) -> String {
        guard source.hasAudio else {
            return AppStrings.text("smartEdit.analysisSpeechNoAudio")
        }
        switch source.speechRecognitionStatus {
        case .available:
            return AppStrings.text(
                source.speechCueCount > 0
                    ? "smartEdit.analysisSpeechRecognized"
                    : "smartEdit.analysisSpeechNoneRecognized"
            )
        case .permissionDenied, .onDeviceUnavailable, .recognitionFailed:
            if source.automaticCutReason == .quietAudio {
                return AppStrings.text("smartEdit.analysisSpeechQuietFallback")
            }
            switch source.speechRecognitionStatus {
            case .permissionDenied:
                return AppStrings.text("smartEdit.analysisSpeechPermission")
            case .onDeviceUnavailable:
                return AppStrings.text("smartEdit.analysisSpeechUnsupported")
            default:
                return AppStrings.text("smartEdit.analysisSpeechFailed")
            }
        case .noAudio:
            return AppStrings.text("smartEdit.analysisSpeechNoAudio")
        }
    }

    private func analysisCutDescription(
        for source: SmartEditAnalysisSummary.Source
    ) -> String {
        guard !source.keptRanges.isEmpty else {
            return AppStrings.text("smartEdit.analysisNoCuts")
        }
        let shown = source.keptRanges.prefix(12).map {
            "\(durationLabel($0.startSeconds))–\(durationLabel($0.endSeconds))"
        }.joined(separator: " · ")
        if source.keptRanges.count > 12 {
            return AppStrings.format(
                "smartEdit.analysisCutTimesMore",
                shown,
                source.keptRanges.count - 12
            )
        }
        return AppStrings.format("smartEdit.analysisCutTimes", shown)
    }

    private func draftTimeline(_ draft: SmartEditDraft) -> some View {
        let voiceSourceIDs = Set(draft.audioSegments.map(\.sourceID))
        return VStack(alignment: .leading, spacing: 14) {
            previewPanel
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.name)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(EditorTheme.text)
                    Text(
                        AppStrings.format(
                            "smartEdit.draftSummary",
                            draft.sources.count,
                            durationLabel(draft.durationSeconds)
                        )
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(EditorTheme.muted)
                }
                Spacer()
                Button {
                    selectedDraftID = nil
                    timelineEditDraft = nil
                    previewSourceID = sources.first?.id
                    previewProjectVideoID = projectVideos.first?.id
                    previewPlayer.pause()
                    previewPlayer.replaceCurrentItem(with: nil)
                    if let source = sources.first {
                        playSource(source)
                    } else if let video = projectVideos.first {
                        playProjectVideo(video)
                    }
                } label: {
                    Label(
                        AppStrings.text("smartEdit.backToMaterials"),
                        systemImage: "arrow.left"
                    )
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
            }

            trackHeader(
                AppStrings.text("smartEdit.voiceTrack"),
                detail: voiceTrackDetail(for: draft),
                symbol: "waveform"
            )
            if draft.audioSegments.isEmpty {
                emptyTrack(AppStrings.text("smartEdit.noAudio"))
            } else {
                ForEach(draft.audioSegments) { segment in
                    if let source = draft.sources.first(where: { $0.id == segment.sourceID }) {
                        trackBlock(
                            title: source.fileName,
                            detail: "\(durationLabel(segment.durationSeconds)) · "
                                + (source.speechCues.isEmpty
                                    ? AppStrings.text("smartEdit.originalAudio")
                                    : AppStrings.format(
                                        "smartEdit.lockedSpeechAndAudio",
                                        source.speechCues.filter(\.isLocked).count
                                    )),
                            icon: "waveform",
                            tint: EditorTheme.accent,
                            locked: segment.isLocked
                        )
                    }
                }
            }

            trackHeader(
                AppStrings.text("smartEdit.pictureTrack"),
                detail: AppStrings.format(
                    "smartEdit.shotCountWithVoice",
                    draft.clips.count,
                    voiceSourceIDs.count
                ),
                symbol: "film"
            )
            if draft.clips.isEmpty {
                emptyTrack(AppStrings.text("smartEdit.noVideo"))
            } else {
                shotControls(for: draft)
                if SmartEditTimelineEditor().canMoveClips(in: draft) {
                    Text(AppStrings.text("smartEdit.cutInOutHint"))
                        .font(.system(size: 10))
                        .foregroundStyle(EditorTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !SmartEditTimelineEditor().canMoveClips(in: draft) {
                    Text(AppStrings.text("smartEdit.reorderSingleSourceHint"))
                        .font(.system(size: 10))
                        .foregroundStyle(EditorTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LazyVStack(spacing: 7) {
                    ForEach(Array(draft.clips.enumerated()), id: \.element.id) { index, clip in
                        shotRow(clip, at: index, in: draft)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func shotControls(for draft: SmartEditDraft) -> some View {
        HStack(spacing: 8) {
            Text(AppStrings.format("smartEdit.shotCount", draft.clips.count))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(EditorTheme.muted)
            Spacer()
            Button {
                insertCurrentPreviewFrame(asNewShot: false)
            } label: {
                Label(
                    AppStrings.text("smartEdit.cutAtPlayhead"),
                    systemImage: "scissors"
                )
            }
            .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
            .disabled(!isPreviewSourceIn(draft))
        }
    }

    private func isPreviewSourceIn(_ draft: SmartEditDraft) -> Bool {
        guard let previewSourceID else { return false }
        return draft.sources.contains(where: { $0.id == previewSourceID })
    }

    private func insertCurrentPreviewFrame(asNewShot: Bool) {
        guard let draft = selectedDraft,
              let sourceID = previewSourceID,
              let source = draft.sources.first(where: { $0.id == sourceID }) else {
            return
        }
        let frameTime = CMTimeGetSeconds(previewPlayer.currentTime())
        guard frameTime.isFinite,
              frameTime > 0.2,
              frameTime < source.durationSeconds - 0.2 else {
            errorMessage = AppStrings.text("smartEdit.playheadCutRangeHint")
            return
        }
        guard let originalClip = draft.clips.first(where: {
            $0.videoSourceID == sourceID &&
                frameTime > $0.videoStartSeconds + 0.1 &&
                frameTime < $0.videoEndSeconds - 0.1
        }) else {
            errorMessage = AppStrings.text("smartEdit.playheadNoCutTarget")
            return
        }
        let targetClip: SmartEditClip
        if let explicitClipID = selectedCutClipID,
           let selectedClip = draft.clips.first(where: { $0.id == explicitClipID }),
           selectedClip.videoSourceID == sourceID {
            targetClip = selectedClip
        } else {
            targetClip = originalClip
        }
        if asNewShot {
            guard let split = SmartEditTimelineEditor().splittingClip(
                targetClip.id,
                at: frameTime,
                in: draft
            ) else { return }
            saveTimelineEdit(split)
        } else {
            guard let trimmed = SmartEditTimelineEditor().trimmingClipEnd(
                targetClip.id,
                to: frameTime,
                in: draft
            ) else { return }
            saveTimelineEdit(trimmed)
        }
        selectedCutClipID = nil
        previewPlayer.seek(
            to: CMTime(seconds: frameTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        previewPlayer.pause()
    }

    private func saveTimelineEdit(_ draft: SmartEditDraft) {
        timelineEditDraft = draft
        selectedDraftID = draft.id
        do {
            try store.save(draft)
            drafts = try store.loadAll()
            errorMessage = nil
        } catch {
            errorMessage = AppStrings.format(
                "smartEdit.saveFailed",
                error.localizedDescription
            )
        }
    }

    private var settingsPanel: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 15) {
            panelTitle(AppStrings.text("smartEdit.analysisSettings"))

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(EditorTheme.accent)
                Text(AppStrings.text("smartEdit.localEngine"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EditorTheme.text)
                Spacer()
                Text(AppStrings.text("smartEdit.current"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(EditorTheme.accent)
            }
            .padding(10)
            .background(EditorTheme.raised, in: RoundedRectangle(cornerRadius: 9))
            .accessibilityLabel(AppStrings.text("smartEdit.localEngineDetail"))

            settingGroup(
                title: AppStrings.text("smartEdit.voiceProtection"),
                detail: AppStrings.text("smartEdit.voiceProtectionDetail"),
                symbol: "waveform"
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(EditorTheme.highlight)
                    Text(AppStrings.text("smartEdit.preserveOriginalVoice"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(EditorTheme.text)
                }
            }

            settingGroup(
                title: AppStrings.text("smartEdit.speechLanguage"),
                detail: AppStrings.text("smartEdit.speechLanguageDetail"),
                symbol: "character.bubble"
            ) {
                EditorInlineTabs(
                    options: ["zh-CN", "en-US", "ja-JP"],
                    selection: speechLocaleIdentifier,
                    title: { speechLanguageTitle($0) },
                    onSelect: { speechLocaleIdentifier = $0 }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.text("smartEdit.modelLaterDetail"))
                    .font(.system(size: 10))
                    .foregroundStyle(EditorTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AppStrings.text("smartEdit.modelFieldsPreview"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(EditorTheme.muted)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            }

            settingGroup(
                title: AppStrings.text("smartEdit.aspectRatio"),
                detail: AppStrings.text("smartEdit.aspectRatioDetail"),
                symbol: "aspectratio"
            ) {
                EditorChoiceTabs(
                    options: ExportAspectRatio.allCases,
                    selection: targetAspectRatio,
                    columns: 3,
                    title: { aspectTitle($0) },
                    onSelect: { targetAspectRatio = $0 }
                )
            }

            settingGroup(
                title: AppStrings.text("smartEdit.activityOffset"),
                detail: AppStrings.text("smartEdit.activityOffsetDetail"),
                symbol: "clock.arrow.circlepath"
            ) {
                HStack(spacing: 7) {
                    TextField(
                        "0.000",
                        value: $activityTimeOffset,
                        format: .number.precision(.fractionLength(3))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    Button {
                        activityTimeOffset = 0
                    } label: {
                        Label(
                            AppStrings.text("smartEdit.resetOffset"),
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                    .buttonStyle(EditorActionButtonStyle(tone: .quiet, size: .compact))
                    Text(AppStrings.text("smartEdit.secondsShort"))
                        .font(.system(size: 10))
                        .foregroundStyle(EditorTheme.muted)
                    Spacer()
                }
            }

            settingGroup(
                title: AppStrings.text("smartEdit.motionData"),
                detail: AppStrings.text("smartEdit.motionDataDetail"),
                symbol: "figure.run"
            ) {
                Text(appModel.project.activitySamples.isEmpty
                    ? AppStrings.text("smartEdit.noMotionData")
                    : AppStrings.format(
                        "smartEdit.motionDataLoaded",
                        appModel.project.activitySamples.count
                    )
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(
                    appModel.project.activitySamples.isEmpty
                        ? EditorTheme.muted : EditorTheme.accent
                )
            }

            settingGroup(
                title: AppStrings.text("smartEdit.duration"),
                detail: AppStrings.text("smartEdit.durationDetail"),
                symbol: "clock"
            ) {
                Text(AppStrings.text("smartEdit.materialDeterminesDuration"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EditorTheme.text)
            }

            settingGroup(
                title: AppStrings.text("smartEdit.resolution"),
                detail: AppStrings.text("smartEdit.resolutionDetail"),
                symbol: "viewfinder"
            ) {
                EditorInlineTabs(
                    options: [480, 720, 1_080, 1_440, 2_160],
                    selection: targetResolution,
                    title: { "\($0)p" },
                    onSelect: { targetResolution = $0 }
                )
            }

            settingGroup(
                title: AppStrings.text("smartEdit.outputDirectory"),
                detail: AppStrings.text(
                    customExportDirectoryURL == nil
                        ? "smartEdit.outputDirectoryFollowsMain"
                        : "smartEdit.outputDirectoryCustomized"
                ),
                symbol: "folder"
            ) {
                Text(
                    selectedExportDirectoryURL?.path ??
                        AppStrings.text("smartEdit.outputDirectoryNotSet")
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EditorTheme.text)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(selectedExportDirectoryURL?.path ?? "")

                HStack(spacing: 8) {
                    Button {
                        chooseExportDirectory()
                    } label: {
                        Label(
                            AppStrings.text(
                                customExportDirectoryURL == nil
                                    ? "smartEdit.chooseOutputDirectory"
                                    : "smartEdit.changeOutputDirectory"
                            ),
                            systemImage: "folder"
                        )
                    }
                    .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                    .disabled(isExporting)

                    if customExportDirectoryURL != nil {
                        Button {
                            resetExportDirectory()
                        } label: {
                            Text(AppStrings.text("smartEdit.followMainDirectory"))
                        }
                        .buttonStyle(EditorActionButtonStyle(tone: .quiet, size: .compact))
                        .disabled(isExporting)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(EditorTheme.accent)
                Text(AppStrings.text("smartEdit.privacyTitle"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EditorTheme.text)
                Text(AppStrings.text("smartEdit.privacyDetail"))
                    .font(.system(size: 11))
                    .foregroundStyle(EditorTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 10))

            Button(role: .destructive) {
                deleteSelectedDraft()
            } label: {
                Label(
                    AppStrings.text("smartEdit.deleteDraft"),
                    systemImage: "trash"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(EditorActionButtonStyle(tone: .destructive))
            .disabled(selectedDraft == nil)
        }
        .padding(16)
        .background(EditorTheme.sidebar)
        }
        .background(EditorTheme.sidebar)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else if let analysisMessage {
                Label(analysisMessage, systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(EditorTheme.muted)
                    .lineLimit(2)
            }
            if let failureMessage = backgroundExportQueue?.failureMessage,
               failureMessage != errorMessage {
                Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                if isAnalyzing {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppStrings.format(
                            "smartEdit.analyzingSource",
                            activeAnalysisFileName ?? ""
                        ))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(EditorTheme.muted)
                        ProgressView(value: analysisProgress)
                            .tint(EditorTheme.accent)
                            .frame(width: 160)
                    }
                    Button {
                        analysisTask?.cancel()
                    } label: {
                        Label(AppStrings.text("ui.common.cancel"), systemImage: "xmark")
                    }
                    .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                } else if isExporting {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppStrings.text("smartEdit.exportingTitle"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(EditorTheme.muted)
                        ProgressView(value: exportProgress)
                            .tint(EditorTheme.accent)
                            .frame(width: 160)
                    }
                } else if let backgroundExportQueue {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(backgroundExportQueue.isComplete
                            ? AppStrings.text(
                                backgroundExportQueue.failureMessage == nil
                                    ? "smartEdit.backgroundExportComplete"
                                    : "smartEdit.backgroundExportFailed"
                            )
                            : AppStrings.format(
                                "smartEdit.exportingBackground",
                                backgroundExportQueue.draft.name
                            )
                        )
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EditorTheme.muted)
                        ProgressView(value: backgroundExportQueue.progress)
                            .tint(EditorTheme.accent)
                            .frame(width: 160)
                    }
                    if backgroundExportQueue.isComplete {
                        Button(action: clearFinishedBackgroundExport) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(EditorTheme.muted)
                        }
                        .buttonStyle(.plain)
                        .help(AppStrings.text("smartEdit.dismissFinishedExport"))
                        if backgroundExportQueue.failureMessage == nil,
                           let url = backgroundExportQueue.outputURL {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.plain)
                            .help(AppStrings.text("smartEdit.revealExport"))
                        }
                    }
                } else if let exportedURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([exportedURL])
                    } label: {
                        Label(
                            AppStrings.text("smartEdit.revealExport"),
                            systemImage: "folder"
                        )
                    }
                    .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                } else {
                    Text(
                        sources.isEmpty
                            ? AppStrings.text("smartEdit.footerHint")
                            : AppStrings.format(
                                "smartEdit.analysisSummary",
                                sources.count,
                                sources.reduce(0) { $0 + $1.speechCues.count }
                            )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(EditorTheme.muted)
                    .lineLimit(2)
                }

                Spacer(minLength: 0)

                if analysisIsComplete &&
                    !sources.isEmpty &&
                    selectedDraft == nil &&
                    backgroundExportQueue == nil {
                    HStack(spacing: 8) {
                        TextField(AppStrings.text("smartEdit.draftName"), text: $draftName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 190)

                        Button(action: generateAndExport) {
                            Label(
                                AppStrings.text("smartEdit.confirmPlanAndGenerate"),
                                systemImage: "square.and.arrow.down"
                            )
                        }
                        .buttonStyle(EditorActionButtonStyle(tone: .outline))
                        .disabled(
                            draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                !analysisIsComplete
                        )
                    }
                }

                if selectedDraft != nil &&
                    !isExporting &&
                    (backgroundExportQueue == nil || backgroundExportQueue?.isComplete == true) {
                    Button(action: exportSelectedDraft) {
                        Label(
                            AppStrings.text("smartEdit.exportMovie"),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .buttonStyle(EditorActionButtonStyle(tone: .outline))
                }

                if backgroundExportQueue != nil && isExporting &&
                    backgroundExportQueue?.isComplete == false {
                    Button(action: continueExportInBackground) {
                        Label(
                            AppStrings.text("smartEdit.continueInBackground"),
                            systemImage: "arrow.down.right.and.arrow.up.left"
                        )
                    }
                    .buttonStyle(EditorActionButtonStyle(tone: .outline))
                }

                Button {
                    analyzeMaterials()
                } label: {
                    Label(
                        AppStrings.text("smartEdit.analyzeLocally"),
                        systemImage: "sparkles"
                    )
                }
                .buttonStyle(EditorActionButtonStyle(tone: .primary))
                .disabled(
                    projectVideos.isEmpty ||
                        isAnalyzing ||
                        isExporting ||
                        backgroundExportQueue != nil
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(EditorTheme.sidebar)
    }

    private func panelTitle(_ title: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EditorTheme.text)
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(EditorTheme.muted)
            }
        }
    }

    private func materialRow(_ video: VideoItem) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "film")
                .foregroundStyle(EditorTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(video.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(EditorTheme.text)
                    .lineLimit(1)
                    .help(video.fileName)
                if appModel.missingResourceVideoIDs.contains(video.id) {
                    Text(AppStrings.text("smartEdit.projectSourceMissing"))
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                } else if let source = sources.first(where: {
                    $0.originalVideoID == video.id
                }) {
                    Text(materialStatus(for: source))
                    .font(.system(size: 10))
                    .foregroundStyle(EditorTheme.muted)
                } else {
                    Text(AppStrings.text("smartEdit.waitingAnalysis"))
                        .font(.system(size: 10))
                        .foregroundStyle(EditorTheme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDraftID = nil
            timelineEditDraft = nil
            if let source = sources.first(where: {
                $0.originalVideoID == video.id
            }) {
                playSource(source)
            } else {
                playProjectVideo(video)
            }
        }
    }

    private func featureNote(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(EditorTheme.accent)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EditorTheme.text)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(14)
        .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 11))
    }

    private func trackHeader(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(EditorTheme.accent)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EditorTheme.text)
            Spacer()
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(EditorTheme.muted)
        }
        .padding(.top, 4)
    }

    private func sourceTrack(_ source: SmartEditMediaSource, isAudio: Bool) -> some View {
        let detail = isAudio
            ? (source.speechCues.isEmpty
                ? AppStrings.text("smartEdit.originalAudio")
                : AppStrings.format("smartEdit.recognizedWords", source.speechCues.count))
            : AppStrings.format(
                "smartEdit.sceneCutCount",
                source.sceneBoundaries.count + 1
            )
        return trackBlock(
            title: source.fileName,
            detail: detail,
            icon: isAudio ? "waveform" : "film",
            tint: isAudio ? EditorTheme.accent : EditorTheme.raised,
            locked: isAudio
        )
        .contentShape(Rectangle())
        .onTapGesture { playSource(source) }
    }

    private var previewPanel: some View {
        let source = selectedPreviewSource
        let previewURL = selectedPreviewURL
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle")
                    .foregroundStyle(EditorTheme.accent)
                Text(AppStrings.text("smartEdit.preview", fallback: "素材预览"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EditorTheme.text)
                Spacer()
                if let previewURL {
                    Text(source?.fileName ?? previewURL.lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(EditorTheme.muted)
                        .lineLimit(1)
                }
                Button {
                    if previewPlayer.rate == 0 {
                        previewPlayer.play()
                    } else {
                        previewPlayer.pause()
                    }
                } label: {
                    Image(systemName: previewPlayer.rate == 0 ? "play.fill" : "pause.fill")
                        .frame(width: 29, height: 26)
                }
                .buttonStyle(EditorActionButtonStyle(tone: .quiet, size: .smallIcon))
                .disabled(previewURL == nil)
                .help(AppStrings.text("smartEdit.togglePreview"))
            }

            if previewURL != nil {
                SmartEditPlaybackView(player: previewPlayer)
                    .frame(maxWidth: .infinity)
                    .frame(height: visiblePreviewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(EditorTheme.separator, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
            } else {
                emptyTrack(AppStrings.text("smartEdit.selectPreviewHint"))
                    .frame(height: 160)
            }

            HStack {
                Spacer()
                Capsule()
                    .fill(EditorTheme.muted)
                    .frame(width: 36, height: 3)
                Spacer()
            }
            .frame(height: 17)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($previewResizeTranslation) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        previewHeight = min(
                            max(190, previewHeight + value.translation.height),
                            max(220, previewAvailableHeight - 180)
                        )
                    }
            )
            .help(AppStrings.text("smartEdit.resizePreview"))
        }
    }

    private var selectedPreviewSource: SmartEditMediaSource? {
        if let previewSourceID,
           let source = selectedDraft?.sources.first(where: { $0.id == previewSourceID })
            ?? sources.first(where: { $0.id == previewSourceID }) {
            return source
        }
        if selectedDraft != nil {
            return selectedDraft?.sources.first
        }
        if let previewProjectVideoID {
            return sources.first(where: { $0.originalVideoID == previewProjectVideoID })
        }
        return sources.first
    }

    private var selectedPreviewURL: URL? {
        if let previewProjectVideoID,
           let video = projectVideos.first(where: { $0.id == previewProjectVideoID }) {
            return appModel.resolvedVideoURLForSmartEdit(video)
        }
        if let source = selectedPreviewSource {
            return source.fileURL
        }
        return projectVideos.first.map(appModel.resolvedVideoURLForSmartEdit)
    }

    private func playProjectVideo(_ video: VideoItem, autoplay: Bool = true) {
        if previewProjectVideoID == video.id, previewPlayer.currentItem != nil {
            return
        }
        do {
            let url = try accessProjectVideo(video)
            previewSourceID = nil
            previewProjectVideoID = video.id
            previewPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
            if autoplay { previewPlayer.play() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func playSource(
        _ source: SmartEditMediaSource,
        at seconds: TimeInterval? = nil
    ) {
        do {
            let url = try resolvePreviewSourceURL(source)
            previewSourceID = source.id
            previewProjectVideoID = nil
            if let item = previewPlayer.currentItem,
               let currentAsset = item.asset as? AVURLAsset,
               currentAsset.url.standardizedFileURL == url.standardizedFileURL {
                if let seconds {
                    previewPlayer.seek(
                        to: CMTime(seconds: seconds, preferredTimescale: 600),
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    )
                }
                return
            }
            previewPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
            if let seconds {
                previewPlayer.seek(
                    to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolvePreviewSourceURL(_ source: SmartEditMediaSource) throws -> URL {
        if let id = source.originalVideoID,
           let video = projectVideos.first(where: { $0.id == id }) {
            return try accessProjectVideo(video)
        }
        guard let bookmark = source.bookmarkData else {
            guard FileManager.default.isReadableFile(atPath: source.fileURL.path) else {
                throw SmartEditWorkspaceError.missingSource(source.fileName)
            }
            return source.fileURL
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale,
              FileManager.default.isReadableFile(atPath: url.path) else {
            throw SmartEditWorkspaceError.staleBookmark(source.fileName)
        }
        let hasAccess = activeSourceAccessURLs.values.contains {
            $0.standardizedFileURL == url.standardizedFileURL
        }
        if !hasAccess {
            let didStart = url.startAccessingSecurityScopedResource()
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                if didStart { url.stopAccessingSecurityScopedResource() }
                throw SmartEditWorkspaceError.permissionDenied(source.fileName)
            }
            if didStart { activeSourceAccessURLs[source.id] = url }
        }
        return url
    }

    private func trackBlock(
        title: String,
        detail: String,
        icon: String,
        tint: Color,
        locked: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint == EditorTheme.raised ? EditorTheme.accent : tint)
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(EditorTheme.text)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(EditorTheme.muted)
                    .lineLimit(2)
            }
            Spacer()
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(EditorTheme.highlight)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        }
    }

    private func shotRow(
        _ clip: SmartEditClip,
        at index: Int,
        in draft: SmartEditDraft
    ) -> some View {
        HStack(spacing: 8) {
            VStack(spacing: 5) {
                Button {
                    moveShot(clip, by: -1, in: draft)
                } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 25, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                .help(AppStrings.text("smartEdit.moveEarlier"))

                Button {
                    moveShot(clip, by: 1, in: draft)
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 25, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(index == draft.clips.count - 1)
                .help(AppStrings.text("smartEdit.moveLater"))
            }
            .foregroundStyle(EditorTheme.text)

            if let source = draft.sources.first(where: { $0.id == clip.videoSourceID }) {
                VStack(alignment: .leading, spacing: 7) {
                    trackBlock(
                        title: source.fileName,
                        detail: "\(durationLabel(clip.videoStartSeconds)) → "
                            + "\(durationLabel(clip.videoEndSeconds))"
                            + (clip.transcript.isEmpty ? "" : " · \(clip.transcript)"),
                        icon: "film",
                        tint: clip.isLocked ? EditorTheme.highlight : EditorTheme.accent,
                        locked: clip.isLocked
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCutClipID = clip.id
                        playSource(source, at: clip.videoStartSeconds)
                    }
                    HStack(spacing: 6) {
                        Text(AppStrings.text("smartEdit.cutStart"))
                            .font(.system(size: 9))
                            .foregroundStyle(EditorTheme.muted)
                        TextField(
                            "0.00",
                            value: Binding(
                                get: { clip.videoStartSeconds },
                                set: { updateShot(clip, start: $0, end: clip.videoEndSeconds) }
                            ),
                            format: .number.precision(.fractionLength(2))
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        Text(AppStrings.text("smartEdit.cutEnd"))
                            .font(.system(size: 9))
                            .foregroundStyle(EditorTheme.muted)
                        TextField(
                            "0.00",
                            value: Binding(
                                get: { clip.videoEndSeconds },
                                set: { updateShot(clip, start: clip.videoStartSeconds, end: $0) }
                            ),
                            format: .number.precision(.fractionLength(2))
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        Text(AppStrings.text("smartEdit.secondsShort"))
                            .font(.system(size: 9))
                            .foregroundStyle(EditorTheme.muted)
                    }
                    .padding(.leading, 4)
                }
            }
        }
    }

    private func moveShot(_ clip: SmartEditClip, by offset: Int, in draft: SmartEditDraft) {
        guard SmartEditTimelineEditor().canMoveClips(in: draft) else {
            errorMessage = AppStrings.text("smartEdit.reorderSingleSourceHint")
            return
        }
        guard let updated = SmartEditTimelineEditor().movingClip(
            clip.id,
            by: offset,
            in: draft
        ) else { return }
        timelineEditDraft = updated
        do {
            try store.save(updated)
            drafts = try store.loadAll()
            selectedDraftID = updated.id
        } catch {
            errorMessage = AppStrings.format(
                "smartEdit.saveFailed",
                error.localizedDescription
            )
        }
    }

    private func updateShot(
        _ clip: SmartEditClip,
        start: TimeInterval,
        end: TimeInterval
    ) {
        guard let draft = selectedDraft,
              let updated = SmartEditTimelineEditor().updatingClipRange(
                clip.id,
                startSeconds: start,
                endSeconds: end,
                in: draft
              ) else {
            errorMessage = AppStrings.text("smartEdit.invalidCutRange")
            return
        }
        timelineEditDraft = updated
        do {
            try store.save(updated)
            drafts = try store.loadAll()
        } catch {
            errorMessage = AppStrings.format("smartEdit.saveFailed", error.localizedDescription)
        }
    }

    private func emptyTrack(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(EditorTheme.muted)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(EditorTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }

    private func settingGroup<Content: View>(
        title: String,
        detail: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EditorTheme.text)
            content()
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(EditorTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }

    private func accessProjectVideo(_ video: VideoItem) throws -> URL {
        let url = appModel.resolvedVideoURLForSmartEdit(video).standardizedFileURL
        if let active = activeSourceAccessURLs[video.id] {
            if active.standardizedFileURL == url,
               FileManager.default.isReadableFile(atPath: url.path) {
                return url
            }
            active.stopAccessingSecurityScopedResource()
            activeSourceAccessURLs.removeValue(forKey: video.id)
        }
        let didStart = url.startAccessingSecurityScopedResource()
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            if didStart { url.stopAccessingSecurityScopedResource() }
            throw SmartEditWorkspaceError.missingSource(video.fileName)
        }
        if didStart { activeSourceAccessURLs[video.id] = url }
        return url
    }

    private func analyzeMaterials() {
        guard !isAnalyzing, !projectVideos.isEmpty else { return }
        let videos = projectVideos
        let projectID = appModel.project.id
        isAnalyzing = true
        analysisIsComplete = false
        analysisFailures.removeAll()
        analysisProgress = 0
        errorMessage = nil
        analysisMessage = AppStrings.text("smartEdit.localPrivacyNotice")
        selectedDraftID = nil
        timelineEditDraft = nil
        previewPlayer.pause()
        previewPlayer.replaceCurrentItem(with: nil)
        previewSourceID = nil
        previewProjectVideoID = nil
        sources.removeAll()
        let analysisLocale = Locale(identifier: speechLocaleIdentifier)
        speechLocaleIdentifier = analysisLocale.identifier
        let analyzer = LocalSmartEditAnalyzer(locale: analysisLocale)
        analysisTask = Task { @MainActor in
            for (index, video) in videos.enumerated() {
                guard !Task.isCancelled, appModel.project.id == projectID else { break }
                guard projectVideos.contains(where: { $0.id == video.id }) else { continue }
                activeAnalysisFileName = video.fileName
                do {
                    let url = try accessProjectVideo(video)
                    let result = try await analyzer.analyze(
                        fileURL: url,
                        originalVideoID: video.id,
                        motionStartSnapshot: video.effectiveCapturedAt,
                        motionOffsetSnapshot: video.activityMatch.timeOffset,
                        progress: { value in
                            Task { @MainActor in
                                analysisProgress = (
                                    Double(index) + min(max(value, 0), 1)
                                ) / Double(videos.count)
                            }
                        }
                    )
                    guard !Task.isCancelled, appModel.project.id == projectID else { break }
                    guard let latest = projectVideos.first(where: { $0.id == video.id }),
                          appModel.resolvedVideoURLForSmartEdit(latest).standardizedFileURL
                            == url.standardizedFileURL else { continue }
                    var source = result.source
                    source.capturedAt = latest.effectiveCapturedAt
                    source.motionStartSnapshot = latest.effectiveCapturedAt
                    source.motionOffsetSnapshot = latest.activityMatch.timeOffset
                    source.overlayConfigurationSnapshot =
                        latest.overlayOverride ?? appModel.project.overlay
                    if url.standardizedFileURL == latest.fileURL.standardizedFileURL,
                       let bookmark = latest.bookmarkData {
                        source.bookmarkData = bookmark
                    }
                    sources.append(source)
                    if previewSourceID == nil {
                        do {
                            let previewURL = try resolvePreviewSourceURL(source)
                            previewSourceID = source.id
                            previewPlayer.replaceCurrentItem(
                                with: AVPlayerItem(url: previewURL)
                            )
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    if let message = result.message {
                        analysisMessage = message
                    }
                } catch {
                    analysisFailures.append(AppStrings.format(
                        "smartEdit.analysisFailed",
                        video.fileName,
                        error.localizedDescription
                    ))
                }
                analysisProgress = Double(index + 1) / Double(videos.count)
            }
            if Task.isCancelled {
                analysisIsComplete = false
                analysisMessage = AppStrings.text("smartEdit.analysisCancelled")
            } else if appModel.project.id != projectID {
                sources.removeAll()
                analysisIsComplete = false
            } else if !analysisFailures.isEmpty ||
                        sources.count != projectVideos.count {
                analysisIsComplete = false
                errorMessage = analysisFailures.first ??
                    AppStrings.text("smartEdit.analysisIncompleteHint")
                analysisMessage = AppStrings.text("smartEdit.analysisIncompleteHint")
            } else if !sources.isEmpty {
                analysisIsComplete = true
                draftName = defaultDraftName()
                analysisMessage = AppStrings.text("smartEdit.analysisReadyToReview")
            }
            isAnalyzing = false
            activeAnalysisFileName = nil
            if !isWindowVisible && !isExporting {
                stopSourceAccess()
            }
        }
    }

    private func generateAndExport() {
        guard analysisIsComplete,
              sources.count == projectVideos.count,
              Set(sources.compactMap(\.originalVideoID)) ==
                Set(projectVideos.map(\.id)) else {
            errorMessage = AppStrings.text("smartEdit.analysisIncompleteHint")
            return
        }
        guard let directory = selectedExportDirectoryURL else {
            errorMessage = AppStrings.text("smartEdit.outputDirectoryRequired")
            return
        }
        let didStartAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                directory.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try ExportDirectoryWriteProbe().verify(directory)
            let draft = SmartEditDraftBuilder().makeAutomaticDraft(
                name: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
                sources: projectVideos.compactMap { video in
                    sources.first(where: { $0.originalVideoID == video.id })
                },
                aspectRatio: targetAspectRatio,
                maximumHeight: targetResolution,
                speechLocaleIdentifier: speechLocaleIdentifier,
                activitySamples: ActivityTimeline().smoothed(
                    samples: appModel.project.activitySamples,
                    level: appModel.project.smoothingLevel
                ),
                activitySourceID: appModel.project.activitySource?.id,
                activityChannel: appModel.project.activitySource,
                activityTimeOffset: activityTimeOffset,
                activityStartSnapshot: appModel.project.activitySource?.timeRange?.start,
                videoTextLanguage: appModel.project.exportSettings.videoTextLanguage,
                overlayConfiguration: appModel.project.overlay
            )
            try store.save(draft)
            drafts = try store.loadAll()
            selectedDraftID = draft.id
            timelineEditDraft = draft
            analysisMessage = AppStrings.text("smartEdit.draftGenerated")
            errorMessage = nil
            exportSelectedDraft()
        } catch {
            errorMessage = AppStrings.format(
                "smartEdit.outputDirectoryError",
                error.localizedDescription
            )
        }
    }

    private func deleteSelectedDraft() {
        guard let selectedDraft else { return }
        do {
            try store.delete(selectedDraft)
            drafts = try store.loadAll()
            if selectedDraftID == selectedDraft.id {
                selectedDraftID = nil
                timelineEditDraft = nil
            }
            exportedURL = nil
            errorMessage = nil
        } catch {
            errorMessage = AppStrings.format(
                "smartEdit.deleteFailed",
                error.localizedDescription
            )
        }
    }

    private func chooseExportDirectory() {
        let panel = NSOpenPanel()
        panel.title = AppStrings.text("smartEdit.outputDirectory")
        panel.prompt = AppStrings.text("ui.panel.chooseFolder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = selectedExportDirectoryURL
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }
        do {
            try ExportDirectoryWriteProbe().verify(url)
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let defaults = UserDefaults.standard
            defaults.set(bookmark, forKey: ExportDirectoryPreference.bookmark)
            defaults.set(url.path, forKey: ExportDirectoryPreference.path)
            customExportDirectoryURL = url
            errorMessage = nil
        } catch {
            errorMessage = AppStrings.format(
                "smartEdit.outputDirectoryError",
                error.localizedDescription
            )
        }
    }

    private func resetExportDirectory() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: ExportDirectoryPreference.bookmark)
        defaults.removeObject(forKey: ExportDirectoryPreference.path)
        customExportDirectoryURL = nil
        errorMessage = nil
    }

    private func restoreExportDirectory() {
        guard let bookmark = UserDefaults.standard.data(
            forKey: ExportDirectoryPreference.bookmark
        ) else {
            customExportDirectoryURL = nil
            return
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isStale else {
            resetExportDirectory()
            errorMessage = AppStrings.text("smartEdit.outputDirectoryExpired")
            return
        }
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }
        guard (try? ExportDirectoryWriteProbe().verify(url)) != nil else {
            resetExportDirectory()
            errorMessage = AppStrings.text("smartEdit.outputDirectoryExpired")
            return
        }
        customExportDirectoryURL = url
    }

    private func exportSelectedDraft() {
        guard let selectedDraft, !isExporting else { return }
        guard let directory = selectedExportDirectoryURL else {
            errorMessage = AppStrings.text("smartEdit.outputDirectoryRequired")
            return
        }
        let didStartAccess = directory.startAccessingSecurityScopedResource()
        do {
            try ExportDirectoryWriteProbe().verify(directory)
            let outputURL = try SmartEditVideoExporter().makeJob(
                from: selectedDraft,
                exportDirectory: directory
            ).outputURL
            let sourceURLs = try beginSourceAccess(for: selectedDraft)
            var exportDraft = selectedDraft
            for index in exportDraft.sources.indices {
                if let resolvedURL = sourceURLs[exportDraft.sources[index].id] {
                    exportDraft.sources[index].fileURL = resolvedURL
                }
            }
            startExport(
                exportDraft,
                to: outputURL,
                directoryAccessURL: didStartAccess ? directory : nil,
                allowsWindowClose: true,
                queueForBackground: true
            )
        } catch {
            if didStartAccess {
                directory.stopAccessingSecurityScopedResource()
            }
            errorMessage = error.localizedDescription
        }
    }

    private func startExport(
        _ draft: SmartEditDraft,
        to url: URL,
        directoryAccessURL: URL?,
        allowsWindowClose: Bool,
        queueForBackground: Bool
    ) {
        isExporting = true
        exportProgress = 0
        errorMessage = nil
        exportedURL = nil
        let exporter = SmartEditVideoExporter()
        let queue: SmartEditBackgroundExportQueue
        if let existing = backgroundExportQueue, allowsWindowClose {
            existing.draft = draft
            existing.outputURL = url
            existing.progress = 0
            existing.isComplete = false
            existing.failureMessage = nil
            queue = existing
        } else {
            queue = SmartEditBackgroundExportQueue(
                draft: draft,
                outputURL: (allowsWindowClose || queueForBackground) ? url : nil
            )
            backgroundExportQueue = (allowsWindowClose || queueForBackground) ? queue : nil
        }
        exportTask = Task { @MainActor in
            defer {
                isExporting = false
                queue.isComplete = true
                stopSourceAccess()
                directoryAccessURL?.stopAccessingSecurityScopedResource()
            }
            do {
                try await exporter.export(draft, to: url) { value in
                    Task { @MainActor in
                        exportProgress = value
                        queue.progress = value
                    }
                }
                exportedURL = url
                queue.outputURL = url
                queue.isComplete = true
                analysisMessage = AppStrings.format(
                    "smartEdit.exportComplete",
                    url.lastPathComponent
                )
            } catch {
                queue.failureMessage = error.localizedDescription
                queue.isComplete = true
                queue.outputURL = nil
                if isWindowVisible {
                    errorMessage = error.localizedDescription
                }
                // 后台导出失败后再次打开工作区也能看见真实失败原因。
                analysisMessage = nil
            }
        }
    }

    private func continueExportInBackground() {
        guard let queue = backgroundExportQueue,
              isExporting,
              !queue.isComplete else { return }
        onClose()
    }

    private func clearFinishedBackgroundExport() {
        guard backgroundExportQueue?.isComplete == true else { return }
        backgroundExportQueue = nil
        exportedURL = nil
        errorMessage = nil
    }

    @State private var activeSourceAccessURLs: [UUID: URL] = [:]

    private func beginSourceAccess(for draft: SmartEditDraft) throws -> [UUID: URL] {
        previewPlayer.pause()
        previewPlayer.replaceCurrentItem(with: nil)
        stopSourceAccess()
        var accessed: [UUID: URL] = [:]
        var resolvedSources: [UUID: URL] = [:]
        do {
            for source in draft.sources {
                if let videoID = source.originalVideoID,
                   let video = projectVideos.first(where: { $0.id == videoID }) {
                    resolvedSources[source.id] = try accessProjectVideo(video)
                    continue
                }
                var resolvedURL: URL
                if let bookmarkData = source.bookmarkData {
                    var isStale = false
                    resolvedURL = try URL(
                        resolvingBookmarkData: bookmarkData,
                        options: [.withSecurityScope],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    guard !isStale else {
                        throw SmartEditWorkspaceError.staleBookmark(source.fileName)
                    }
                } else {
                    resolvedURL = source.fileURL
                }
                let didStart = resolvedURL.startAccessingSecurityScopedResource()
                guard FileManager.default.isReadableFile(atPath: resolvedURL.path) else {
                    if didStart { resolvedURL.stopAccessingSecurityScopedResource() }
                    throw SmartEditWorkspaceError.missingSource(source.fileName)
                }
                if didStart {
                    accessed[source.id] = resolvedURL
                }
                resolvedSources[source.id] = resolvedURL
            }
            activeSourceAccessURLs.merge(accessed) { _, new in new }
            return resolvedSources
        } catch {
            accessed.values.forEach { $0.stopAccessingSecurityScopedResource() }
            stopSourceAccess()
            throw error
        }
    }

    private func stopSourceAccess() {
        for url in activeSourceAccessURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
        activeSourceAccessURLs.removeAll()
    }

    private func loadDrafts() {
        do {
            drafts = try store.loadAll()
            if selectedDraftID == nil,
               let video = projectVideos.first(where: { $0.id == appModel.selectedVideoID })
                    ?? projectVideos.first {
                playProjectVideo(video, autoplay: false)
            }
        } catch {
            errorMessage = AppStrings.format(
                "smartEdit.loadFailed",
                error.localizedDescription
            )
        }
    }

    private func resetCurrentProjectMaterial() {
        previewPlayer.pause()
        previewPlayer.replaceCurrentItem(with: nil)
        previewSourceID = nil
        previewProjectVideoID = nil
        selectedDraftID = nil
        timelineEditDraft = nil
        sources.removeAll()
        analysisIsComplete = false
        analysisFailures.removeAll()
        analysisMessage = nil
        if !isAnalyzing && !isExporting {
            stopSourceAccess()
        }
    }

    private func defaultDraftName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return AppStrings.format("smartEdit.defaultDraftName", formatter.string(from: Date()))
    }

    private func materialStatus(for source: SmartEditMediaSource) -> String {
        guard source.hasAudio else {
            return AppStrings.format(
                "smartEdit.materialNoAudio",
                durationLabel(source.durationSeconds)
            )
        }
        guard !source.speechCues.isEmpty else {
            return AppStrings.format(
                "smartEdit.materialAnalyzedWithoutSpeech",
                durationLabel(source.durationSeconds)
            )
        }
        return AppStrings.format(
            "smartEdit.materialAnalyzed",
            durationLabel(source.durationSeconds),
            source.speechCues.count
        )
    }

    private func voiceTrackDetail(for draft: SmartEditDraft) -> String {
        guard !draft.audioSegments.isEmpty else {
            return AppStrings.text("smartEdit.noAudio")
        }
        let hasRecognizedSpeech = draft.sources.contains {
            !$0.speechCues.isEmpty
        }
        return hasRecognizedSpeech
            ? AppStrings.format(
                "smartEdit.lockedSpeechCount",
                draft.preservedSpeechCueCount
            )
            : AppStrings.text("smartEdit.fullVoiceTrackRetained")
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }

    private func aspectTitle(_ ratio: ExportAspectRatio) -> String {
        switch ratio {
        case .source: AppStrings.text("ui.workspace.aspectRatio.sourceShort")
        case .landscape16x9: "16:9"
        case .portrait9x16: "9:16"
        case .square: "1:1"
        case .portrait4x5: "4:5"
        case .landscape4x3: "4:3"
        case .portrait3x4: "3:4"
        }
    }

    private func speechLanguageTitle(_ localeIdentifier: String) -> String {
        switch localeIdentifier {
        case "zh-CN": AppStrings.text("smartEdit.languageChinese")
        case "en-US": AppStrings.text("smartEdit.languageEnglish")
        case "ja-JP": AppStrings.text("smartEdit.languageJapanese")
        default: localeIdentifier
        }
    }

}

@Observable
@MainActor
final class SmartEditBackgroundExportQueue {
    var draft: SmartEditDraft
    var outputURL: URL?
    var progress = 0.0
    var isComplete = false
    var failureMessage: String?

    init(draft: SmartEditDraft, outputURL: URL? = nil) {
        self.draft = draft
        self.outputURL = outputURL
    }
}

private enum SmartEditWorkspaceError: LocalizedError {
    case staleBookmark(String)
    case missingSource(String)
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case let .staleBookmark(name):
            AppStrings.format("smartEdit.sourceBookmarkStale", name)
        case let .missingSource(name):
            AppStrings.format("smartEdit.export.sourceMissing", name)
        case let .permissionDenied(name):
            AppStrings.format("smartEdit.sourceAccessDenied", name)
        }
    }
}
