import AppKit
import AVFoundation
import Combine
import IOKit.pwr_mgt
import RunOverlayCore
import UniformTypeIdentifiers

extension UTType {
    static let runOverlayProject = UTType(exportedAs: "com.runoverlay.project")
    static let runOverlayTemplate = UTType(exportedAs: "com.runoverlay.template")
    static let fitActivity = UTType(importedAs: "com.garmin.fit")
    static let gpxActivity = UTType(importedAs: "com.topografix.gpx")
}

enum OverlayEditingScope: String, CaseIterable {
    case project
    case currentVideo

    var displayName: String {
        switch self {
        case .project: AppStrings.text("scope.project")
        case .currentVideo: AppStrings.text("scope.currentVideo")
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    private struct EditorState: Equatable {
        let project: RunOverlayProject
        let drafts: OverlayDraftLibrary
        let selectedVideoID: UUID?
        let selectedElementID: UUID?
        let exportVideoSelection: Set<UUID>?
        let editingScope: OverlayEditingScope
        let exportDirectoryURL: URL?
        let projectFileURL: URL?
        let language: RunOverlayLanguage
    }

    private enum PreferencesKey {
        static let exportDirectoryBookmark = "导出目录书签"
        static let exportDirectoryPath = "导出目录路径"
        static let coverAutoSavePath = "封面编辑自动保存路径"
        static let coverSelectedVideoID = "封面编辑上次选中的视频"
    }

    @Published private(set) var project = RunOverlayProject()
    @Published private(set) var overlayDraftLibrary = OverlayDraftLibrary()
    @Published private(set) var selectedLanguage = RunOverlayLocalization.language
    @Published var selectedVideoID: UUID?
    @Published private(set) var exportVideoSelection: Set<UUID>?
    @Published private(set) var isImportingVideos = false
    @Published private(set) var isImportingActivity = false
    @Published private(set) var isSavingSnapshot = false
    @Published var snapshotIncludesDataLayer = false
    @Published var isCoverEditorPresented = false
    /// 封面编辑独立窗口当前编辑的视频；变化时窗口切换目标视频。
    @Published var coverEditorVideoID: UUID?
    @Published private(set) var coverEditorFrameTime: TimeInterval?
    @Published private(set) var playbackTime: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published var overlayEditingScope: OverlayEditingScope = .project
    @Published var selectedOverlayElementID: UUID?
    @Published private(set) var exportJobs: [ExportJob] = []
    @Published private(set) var exportDirectoryDisplayName: String?
    @Published var isExportQueuePresented = false
    /// 队列仍在执行时为真；关闭弹窗仅允许浏览与制作封面，不停止编码。
    @Published private(set) var exportBatchHasStarted = false
    @Published private(set) var isExporting = false
    @Published private(set) var isPackagingProject = false
    @Published private(set) var missingResourceVideoIDs: Set<UUID> = []
    @Published private(set) var missingVideoTimeResourceIDs: Set<UUID> = []
    @Published private(set) var isActivityResourceMissing = false
    @Published private(set) var videoThumbnails: [UUID: NSImage] = [:]
    @Published private(set) var exportSpaceEstimate: DiskSpaceEstimate?
    @Published var presentedError: PresentedError?

    let player = AVPlayer()

    private let metadataReader = VideoMetadataReader()
    private let thumbnailReader = VideoThumbnailReader()
    private let activityParser = ActivityParser()
    private let activityMatcher = VideoActivityMatcher()
    private let activityTimeline = ActivityTimeline()
    private let projectCodec = ProjectFileCodec()
    private let overlayDraftStore = OverlayDraftStore()
    private let overlayDraftTransferService = OverlayDraftTransferService()
    private var activityProgressCalculator = ActivityProgressCalculator()
    @Published private(set) var elevationProfile = ElevationProfile()
    private var projectFileURL: URL?
    private var coverSaveTask: Task<Void, Never>?
    private var activeSecurityScopedURL: URL?
    private var activeTimeResourceAccessURL: URL?
    private var playerTimeObserver: Any?
    private var playerCompletionObserver: AnyCancellable?
    private var activeProjectFileAccessURL: URL?
    private var pendingPlaybackSeek: UUID?
    private var previewSamples: [ActivitySample] = []
    @Published private var editHistory = EditHistory<EditorState>()
    private var pendingEdit: (action: String, before: EditorState)?
    private var lastContinuousEdit: (action: String, at: Date, before: EditorState)?
    private var exportDirectoryURL: URL?
    private var activeExportDirectoryAccessURL: URL?
    private var thumbnailLoadingIDs: Set<UUID> = []
    private var activeExportIDs: Set<UUID> = []
    private var exportTasks: [UUID: Task<Void, Never>] = [:]
    private var exporters: [UUID: VideoExporter] = [:]
    private var sleepAssertionID: IOPMAssertionID = 0

    var canUndo: Bool { canEditHistory && editHistory.canUndo }
    var canRedo: Bool { canEditHistory && editHistory.canRedo }
    var undoActions: [String] {
        editHistory.undoSteps.reversed().map { AppStrings.text($0.action) }
    }
    var redoActions: [String] {
        editHistory.redoSteps.reversed().map { AppStrings.text($0.action) }
    }
    private var canEditHistory: Bool {
        !exportBatchHasStarted && !isImportingVideos && !isImportingActivity &&
            !isPackagingProject
    }

    var exportBatchCompletedCount: Int {
        exportJobs.filter { $0.status == .completed }.count
    }

    var exportBatchUnsuccessfulCount: Int {
        exportJobs.filter { job in
            switch job.status {
            case .failed, .cancelled: true
            case .waiting, .exporting, .completed: false
            }
        }.count
    }

    var exportBatchIsFinished: Bool {
        !exportJobs.isEmpty &&
            exportJobs.allSatisfy { job in
                switch job.status {
                case .waiting, .exporting: false
                case .completed, .failed, .cancelled: true
                }
            }
    }

    /// 导出弹窗收起后允许浏览视频与制作封面；队列仍由 AppModel 持续运行。
    var canBrowseVideosDuringExport: Bool {
        ExportQueueInteractionPolicy.canBrowseVideos(
            batchRunning: exportBatchHasStarted,
            queuePresented: isExportQueuePresented
        )
    }

    var exportBatchProgress: Double {
        guard !exportJobs.isEmpty else {
            return 0
        }
        let progress = exportJobs.reduce(0) { total, job in
            switch job.status {
            case .waiting:
                return total
            case .exporting:
                return total + min(max(job.progress, 0), 1)
            case .completed, .failed, .cancelled:
                return total + 1
            }
        }
        return progress / Double(exportJobs.count)
    }

    func setLanguage(_ language: RunOverlayLanguage) {
        guard selectedLanguage != language else {
            return
        }
        let before = editorState
        RunOverlayLocalization.language = language
        selectedLanguage = language
        recordHistory("ui.history.language", before: before)
    }

    init() {
        playerTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, self.pendingPlaybackSeek == nil else { return }
                self.playbackTime = max(0, time.seconds.isFinite ? time.seconds : 0)
            }
        }
        playerCompletionObserver = NotificationCenter.default.publisher(
            for: .AVPlayerItemDidPlayToEndTime
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] notification in
            guard let self,
                  let item = notification.object as? AVPlayerItem,
                  self.player.currentItem === item else {
                return
            }
            self.isPlaying = false
            if let duration = self.selectedVideo?.metadata.durationSeconds {
                self.playbackTime = duration
            }
        }
        do {
            overlayDraftLibrary = try overlayDraftStore.load()
            if let defaultOverlay = overlayDraftLibrary.defaultConfiguration {
                project.overlay = defaultOverlay
            }
        } catch {
            presentedError = PresentedError(
                title: AppStrings.text("ui.draft.loadFailure"),
                message: error.localizedDescription
            )
        }
        restoreExportDirectory()
        restoreUnsavedCoverProject()
    }

    var selectedVideo: VideoItem? {
        guard let selectedVideoID else {
            return nil
        }
        return project.videos.first { $0.id == selectedVideoID }
    }

    /// 智能成片与主工作台使用相同的素材定位规则，包括打包项目中的相对路径。
    func resolvedVideoURLForSmartEdit(_ video: VideoItem) -> URL {
        resolveURL(for: video)
    }

    /// 智能成片未单独设置保存目录时，沿用主功能的导出目录。
    var defaultSmartEditExportDirectoryURL: URL? {
        exportDirectoryURL
    }

    var videosSelectedForExport: Set<UUID> {
        exportVideoSelection ?? Set(project.videos.map(\.id))
    }

    var canDeleteSelectedVideo: Bool {
        guard let selectedVideoID else { return false }
        return exportVideoSelection == nil || exportVideoSelection == [selectedVideoID]
    }

    var canClearVideos: Bool {
        !project.videos.isEmpty && canEditHistory
    }

    var canClearActivity: Bool {
        (project.activitySource != nil || !project.activitySamples.isEmpty) &&
            canEditHistory
    }

    var activitySourceStatusMessage: String? {
        guard isActivityResourceMissing,
              let source = project.activitySource else {
            return nil
        }
        return AppStrings.format(
            "ui.activity.sourceMissingDetail",
            source.fileName
        )
    }

    func setExportVideoSelection(
        _ ids: Set<UUID>,
        previewIfSingle: Bool = true,
        recordsHistory: Bool = true
    ) {
        let before = editorState
        let validIDs = Set(project.videos.map(\.id))
        let selection = ids.intersection(validIDs)
        if exportVideoSelection != selection {
            exportVideoSelection = selection
        }
        if previewIfSingle,
           selection.count == 1,
           let id = selection.first,
           selectedVideoID != id {
            selectVideo(id)
        }
        if recordsHistory && !exportBatchHasStarted {
            recordHistory("ui.history.videoSelection", before: before)
        }
    }

    func recordExportSelectionChange(from previous: Set<UUID>?) {
        guard !exportBatchHasStarted else { return }
        guard previous != exportVideoSelection else { return }
        let current = editorState
        let before = EditorState(
            project: current.project,
            drafts: current.drafts,
            selectedVideoID: current.selectedVideoID,
            selectedElementID: current.selectedElementID,
            exportVideoSelection: previous,
            editingScope: current.editingScope,
            exportDirectoryURL: current.exportDirectoryURL,
            projectFileURL: current.projectFileURL,
            language: current.language
        )
        recordHistory("ui.history.videoSelection", before: before)
    }

    var currentActivitySample: ActivitySample? {
        guard
            let selectedVideo,
            let capturedAt = selectedVideo.effectiveCapturedAt
        else {
            return nil
        }
        let timestamp = capturedAt.addingTimeInterval(
            selectedVideo.activityMatch.timeOffset + playbackTime
        )
        return activityTimeline.sample(at: timestamp, in: previewSamples)
    }

    var currentActivityProgress: ActivityProgress? {
        activityProgressCalculator.progress(for: currentActivitySample)
    }

    var currentVideoClockTime: Date? {
        guard let selectedVideo,
              let capturedAt = selectedVideo.effectiveCapturedAt else {
            return nil
        }
        return capturedAt.addingTimeInterval(
            selectedVideo.activityMatch.timeOffset + playbackTime
        )
    }

    var routeCoordinates: [GeoCoordinate] {
        previewSamples.compactMap(\.coordinate)
    }

    var effectiveOverlayConfiguration: OverlayConfiguration {
        selectedVideo?.overlayOverride ?? project.overlay
    }

    var editingOverlayConfiguration: OverlayConfiguration {
        guard overlayEditingScope == .currentVideo else {
            return project.overlay
        }
        return selectedVideo?.overlayOverride ?? project.overlay
    }

    func outputPlan(for video: VideoItem) -> VideoOutputPlan {
        VideoOutputPlan(video: video, defaults: project.exportSettings)
    }

    func outputWarningDescription(for plan: VideoOutputPlan) -> String {
        AppStrings.format(
            "ui.video.aspectMismatchDetail",
            plan.rotatedDimensions.displayText,
            plan.aspectRatio.displayName
        )
    }

    func createNewProject() {
        guard !exportBatchHasStarted else {
            presentedError = PresentedError(
                title: AppStrings.text("ui.error.projectChangeDuringExportTitle"),
                message: AppStrings.text("ui.error.projectChangeDuringExportMessage")
            )
            return
        }
        isCoverEditorPresented = false
        coverEditorVideoID = nil
        coverEditorFrameTime = nil
        if coverSaveTask != nil, !flushCoverAutoSave() { return }
        pausePlayback()
        coverSaveTask?.cancel()
        discardCoverAutoSaveForCurrentProject()
        releaseActiveTimeResourceAccess()
        releaseActiveVideoAccess()
        player.replaceCurrentItem(with: nil)
        project = RunOverlayProject()
        videoThumbnails.removeAll()
        exportVideoSelection = nil
        if let defaultOverlay = overlayDraftLibrary.defaultConfiguration {
            project.overlay = defaultOverlay
        }
        previewSamples = []
        elevationProfile = ElevationProfile()
        projectFileURL = nil
        selectedVideoID = nil
        missingResourceVideoIDs = []
        missingVideoTimeResourceIDs = []
        selectedOverlayElementID = nil
        clearHistory()
        playbackTime = 0
    }

    @discardableResult
    func importVideos(
        _ urls: [URL],
        timeResourcesByVideoURL: [URL: VideoTimeResource] = [:]
    ) -> Task<Void, Never>? {
        guard !exportBatchHasStarted else {
            return nil
        }
        let newURLs = urls.filter { candidate in
            !project.videos.contains {
                $0.fileURL.standardizedFileURL == candidate.standardizedFileURL
            }
        }
        guard !newURLs.isEmpty else {
            return nil
        }

        isImportingVideos = true

        return Task {
            var imported: [VideoItem] = []
            var failures: [String] = []

            for url in newURLs {
                var timeResource = timeResourcesByVideoURL[
                    url.resolvingSymlinksInPath().standardizedFileURL
                ]
                let didStartSidecarAccess =
                    timeResource?.fileURL.startAccessingSecurityScopedResource() ?? false
                defer {
                    if didStartSidecarAccess {
                        timeResource?.fileURL.stopAccessingSecurityScopedResource()
                    }
                }

                let didStartAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    let metadata = try await metadataReader.read(from: url)
                    let bookmark = try? url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    if didStartSidecarAccess, let sidecarURL = timeResource?.fileURL {
                        timeResource?.bookmarkData = try? sidecarURL.bookmarkData(
                            options: .withSecurityScope,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                        timeResource?.resourceRelativePath = nil
                    }
                    imported.append(
                        VideoItem(
                            fileName: url.lastPathComponent,
                            fileURL: url,
                            bookmarkData: bookmark,
                            metadata: metadata,
                            timeResource: timeResource
                        )
                    )
                } catch {
                    failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                }
            }

            let before = editorState
            project.videos.append(contentsOf: imported)
            project.videos.sort {
                ($0.effectiveCapturedAt ?? .distantFuture) <
                ($1.effectiveCapturedAt ?? .distantFuture)
            }
            rematchAllVideos()
            refreshMissingResources()
            isImportingVideos = false

            if selectedVideoID == nil, let first = imported.first {
                selectVideo(first.id)
            }
            for video in imported {
                loadThumbnail(for: video)
            }
            if !imported.isEmpty {
                touchProject()
                recordHistory("ui.history.importVideos", before: before)
            }

            if !failures.isEmpty {
                presentedError = PresentedError(
                    title: AppStrings.text("ui.error.partialVideoImportTitle"),
                    message: failures.joined(separator: "\n")
                )
            }
        }
    }

    func presentVideoImportPanel() {
        let panel = NSOpenPanel()
        panel.title = AppStrings.text("ui.panel.importVideosTitle")
        panel.prompt = AppStrings.text("ui.panel.importVideosPrompt")
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK else {
            return
        }
        importDroppedURLs(panel.urls)
    }

    func presentActivityImportPanel() {
        let panel = NSOpenPanel()
        panel.title = AppStrings.text("ui.panel.importActivityTitle")
        panel.prompt = AppStrings.text("ui.panel.importActivityPrompt")
        panel.allowedContentTypes = [.fitActivity, .gpxActivity]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        _ = importActivity(url)
    }

    func importDroppedURLs(_ droppedURLs: [URL]) {
        guard !exportBatchHasStarted, !droppedURLs.isEmpty else {
            return
        }

        Task {
            let didStartAccessing = droppedURLs.filter {
                $0.startAccessingSecurityScopedResource()
            }
            defer {
                didStartAccessing.forEach {
                    $0.stopAccessingSecurityScopedResource()
                }
            }

            let batch = MediaDropScanner().scan(droppedURLs)
            let videosWithoutScannedSidecar = batch.videoURLs.filter {
                batch.timeResourcesByVideoURL[
                    $0.resolvingSymlinksInPath().standardizedFileURL
                ] == nil
            }
            var pairedTimeResources = matchingTimeResources(
                for: videosWithoutScannedSidecar
            )
            for (videoURL, sidecarURL) in batch.timeResourcesByVideoURL {
                let didStartAccess = sidecarURL.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccess {
                        sidecarURL.stopAccessingSecurityScopedResource()
                    }
                }
                pairedTimeResources[videoURL.standardizedFileURL] =
                    VideoTimeResource(
                        fileName: sidecarURL.lastPathComponent,
                        fileURL: sidecarURL,
                        bookmarkData: createBookmark(for: sidecarURL),
                        capturedAt: VideoTimeResourceReader().capturedAt(
                            from: sidecarURL
                        )
                        )
            }
            attachTimeResourcesToExistingVideos(pairedTimeResources)
            if let projectURL = batch.projectURLs.first {
                openProject(at: projectURL)
            }
            var importTasks: [Task<Void, Never>] = []
            if !batch.videoURLs.isEmpty,
               let task = importVideos(
                batch.videoURLs,
                timeResourcesByVideoURL: pairedTimeResources
               ) {
                importTasks.append(task)
            }
            if let activityURL = batch.activityURLs.first {
                importTasks.append(importActivity(activityURL))
            }
            for task in importTasks {
                await task.value
            }
            var notes: [String] = []
            if batch.activityURLs.count > 1 {
                notes.append(
                    AppStrings.format("ui.error.activityCountNote", batch.activityURLs.count)
                )
            }
            if batch.videoURLs.isEmpty,
               batch.activityURLs.isEmpty,
               batch.projectURLs.isEmpty {
                notes.append(AppStrings.text("ui.error.folderImportEmpty"))
            }
            if !notes.isEmpty {
                presentedError = PresentedError(
                    title: AppStrings.text("ui.error.folderImportTitle"),
                    message: notes.joined(separator: "\n")
                )
            }
        }
    }

    func selectVideo(_ id: UUID, preservesElementSelection: Bool = false) {
        guard let video = project.videos.first(where: { $0.id == id }) else {
            return
        }

        selectedVideoID = id
        if !preservesElementSelection {
            selectedOverlayElementID = nil
        }
        pausePlayback()
        releaseActiveTimeResourceAccess()
        releaseActiveVideoAccess()

        let url = resolveURL(for: video)
        let didStartAccess = url.startAccessingSecurityScopedResource()
        if didStartAccess {
            activeSecurityScopedURL = url
        }
        if let resource = video.timeResource {
            let resourceURL = resolveURL(for: resource)
            if resourceURL.startAccessingSecurityScopedResource() {
                activeTimeResourceAccessURL = resourceURL
            }
        }
        if FileManager.default.isReadableFile(atPath: url.path) {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        } else {
            player.replaceCurrentItem(with: nil)
        }
        playbackTime = 0
    }

    func removeSelectedVideo() {
        guard !exportBatchHasStarted,
              canDeleteSelectedVideo,
              let selectedVideoID else {
            return
        }

        pausePlayback()
        recordUndoCheckpoint("ui.history.deleteVideo")
        project.videos.removeAll { $0.id == selectedVideoID }
        exportVideoSelection?.remove(selectedVideoID)
        self.selectedVideoID = nil
        missingVideoTimeResourceIDs.remove(selectedVideoID)
        releaseActiveTimeResourceAccess()
        releaseActiveVideoAccess()
        player.replaceCurrentItem(with: nil)
        if let first = project.videos.first {
            selectVideo(first.id)
        }
        refreshMissingResources()
        touchProject()
    }

    func clearVideos() {
        guard canClearVideos else { return }

        pausePlayback()
        recordUndoCheckpoint("ui.history.clearVideos")
        releaseActiveTimeResourceAccess()
        releaseActiveVideoAccess()
        player.replaceCurrentItem(with: nil)
        project.videos.removeAll()
        exportVideoSelection = nil
        selectedVideoID = nil
        selectedOverlayElementID = nil
        missingResourceVideoIDs.removeAll()
        missingVideoTimeResourceIDs.removeAll()
        videoThumbnails.removeAll()
        playbackTime = 0
        refreshMissingResources()
        touchProject()
    }

    func clearActivity() {
        guard canClearActivity else { return }

        recordUndoCheckpoint("ui.history.clearActivity")
        project.clearActivity()
        rebuildPreviewSamples()
        rematchAllVideos()
        refreshMissingResources()
        touchProject()
    }

    @discardableResult
    func importActivity(_ url: URL) -> Task<Void, Never> {
        guard !exportBatchHasStarted else {
            return Task {}
        }
        isImportingActivity = true

        return Task {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
                isImportingActivity = false
            }

            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try ActivityParser().parse(from: url)
                }.value
                let bookmark = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                let before = editorState
                project.activitySource = ActivitySource(
                    fileName: url.lastPathComponent,
                    fileURL: url,
                    bookmarkData: bookmark,
                    kind: parsed.kind,
                    timeRange: parsed.timeRange,
                    sampleCount: parsed.samples.count,
                    availableChannels: parsed.availableChannels
                )
                project.activitySamples = parsed.samples
                rebuildPreviewSamples()
                rematchAllVideos()
                refreshMissingResources()
                touchProject()
                recordHistory("ui.history.importActivity", before: before)
            } catch {
                presentedError = PresentedError(
                    title: AppStrings.text("ui.error.activityImportTitle"),
                    message: error.localizedDescription
                )
            }
        }
    }

    func setSelectedVideoTimeOffset(_ offset: TimeInterval) {
        guard
            let selectedVideoID,
            let index = project.videos.firstIndex(where: { $0.id == selectedVideoID })
        else {
            return
        }

        recordUndoCheckpoint("ui.history.timeOffset")
        let video = project.videos[index]
        project.videos[index].activityMatch = activityMatcher.match(
            videoStart: video.effectiveCapturedAt,
            duration: video.metadata.durationSeconds,
            activityRange: project.activitySource?.timeRange,
            timeOffset: offset,
            calibrationMethod: .timeOffset
        )
        touchProject()
    }

    func setVideoCapturedAt(_ date: Date?, for id: UUID) {
        guard !exportBatchHasStarted,
              let index = project.videos.firstIndex(where: { $0.id == id }),
              project.videos[index].manualCapturedAt != date else {
            return
        }
        recordUndoCheckpoint("ui.history.captureTime")
        project.videos[index].manualCapturedAt = date
        rematchAllVideos()
        touchProject()
    }

    func calibrateSelectedVideo(to sample: ActivitySample) {
        guard
            let selectedVideoID,
            let index = project.videos.firstIndex(where: { $0.id == selectedVideoID }),
            let capturedAt = project.videos[index].effectiveCapturedAt
        else {
            return
        }

        recordUndoCheckpoint("ui.history.calibrate")
        let offset = sample.timestamp.timeIntervalSince(capturedAt) - playbackTime
        let video = project.videos[index]
        let videoStart = video.effectiveCapturedAt
        project.videos[index].activityMatch = activityMatcher.match(
            videoStart: videoStart,
            duration: video.metadata.durationSeconds,
            activityRange: project.activitySource?.timeRange,
            timeOffset: offset,
            calibrationMethod: .routePosition
        )
        touchProject()
    }

    func setSmoothingLevel(_ level: SmoothingLevel) {
        guard project.smoothingLevel != level else {
            return
        }
        recordUndoCheckpoint("ui.history.smoothing")
        project.smoothingLevel = level
        rebuildPreviewSamples()
        touchProject()
    }

    func setExportCodec(_ codec: ExportSettings.Codec) {
        guard project.exportSettings.codec != codec else {
            return
        }
        recordUndoCheckpoint("ui.history.codec")
        project.exportSettings.codec = codec
        touchProject()
    }

    func setExportAspectRatio(_ aspectRatio: ExportAspectRatio) {
        guard project.exportSettings.aspectRatio != aspectRatio else {
            return
        }
        recordUndoCheckpoint("ui.history.aspectRatio")
        project.exportSettings.aspectRatio = aspectRatio
        touchProject()
    }

    func setVideoTextLanguage(_ language: VideoTextLanguage) {
        guard project.exportSettings.videoTextLanguage != language else {
            return
        }
        recordUndoCheckpoint("ui.history.videoText")
        project.exportSettings.videoTextLanguage = language
        touchProject()
    }

    func setExportMaximumHeight(_ height: Int) {
        let supportedHeights = [480, 720, 1_080, 1_440, 2_160]
        let value = supportedHeights.min {
            abs($0 - height) < abs($1 - height)
        } ?? 1_080
        guard project.exportSettings.maximumHeight != value else {
            return
        }
        recordUndoCheckpoint("ui.history.resolution")
        project.exportSettings.maximumHeight = value
        touchProject()
    }

    func setVideoRotation(_ rotation: VideoRotation, for id: UUID) {
        guard !exportBatchHasStarted,
              let index = project.videos.firstIndex(where: { $0.id == id }),
              project.videos[index].rotation != rotation else {
            return
        }
        recordUndoCheckpoint("ui.history.videoRotation")
        project.videos[index].rotation = rotation
        touchProject()
    }

    func rotateVideo(_ id: UUID, clockwise: Bool) {
        guard !exportBatchHasStarted,
              let index = project.videos.firstIndex(where: { $0.id == id }) else {
            return
        }
        setVideoRotation(
            project.videos[index].rotation.rotated(clockwise: clockwise),
            for: id
        )
    }

    func setExportParallelTaskCount(_ count: Int) {
        let value = min(max(count, 1), 3)
        guard project.exportSettings.parallelTaskCount != value else {
            return
        }
        recordUndoCheckpoint("ui.history.parallel")
        project.exportSettings.parallelTaskCount = value
        touchProject()
    }

    func presentExportQueue() {
        guard !project.videos.isEmpty || !exportJobs.isEmpty else {
            return
        }
        for video in project.videos {
            loadThumbnail(for: video)
        }
        isExportQueuePresented = true
    }

    func chooseExportDirectory() {
        guard !exportBatchHasStarted else {
            return
        }
        _ = selectExportDirectory()
    }

    func configureExportDirectory() {
        guard !exportBatchHasStarted else {
            return
        }
        _ = selectExportDirectory()
    }

    @discardableResult
    private func selectExportDirectory() -> Bool {
        let panel = NSOpenPanel()
        panel.title = AppStrings.text("ui.panel.exportFolderTitle")
        panel.prompt = AppStrings.text("ui.panel.chooseFolder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }
        return setExportDirectory(url)
    }

    @discardableResult
    private func setExportDirectory(
        _ url: URL,
        recordsHistory: Bool = true
    ) -> Bool {
        let before = editorState
        let didStartAccess = url.startAccessingSecurityScopedResource()
        do {
            try ExportDirectoryWriteProbe().verify(url)
        } catch {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
            presentExportDirectoryAccessError(error)
            return false
        }
        // 不要在同一路径重选时先释放旧授权；保留新的安全作用域直至整批结束。
        releaseExportDirectoryAccess()
        if didStartAccess {
            activeExportDirectoryAccessURL = url
        }
        exportDirectoryURL = url
        exportDirectoryDisplayName = url.path
        let defaults = UserDefaults.standard
        let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(url.path, forKey: PreferencesKey.exportDirectoryPath)
        defaults.set(bookmark, forKey: PreferencesKey.exportDirectoryBookmark)
        updateWaitingExportDestinations()
        if recordsHistory {
            recordHistory("ui.history.exportDirectory", before: before)
        }
        return true
    }

    private func restoreExportDirectory() {
        let defaults = UserDefaults.standard
        var restoredURL: URL?
        if let bookmark = defaults.data(
            forKey: PreferencesKey.exportDirectoryBookmark
        ) {
            var isStale = false
            restoredURL = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
        if restoredURL == nil,
           let path = defaults.string(forKey: PreferencesKey.exportDirectoryPath) {
            restoredURL = URL(fileURLWithPath: path, isDirectory: true)
        }
        guard let url = restoredURL else {
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return
        }
        let didStartAccess = url.startAccessingSecurityScopedResource()
        do {
            try ExportDirectoryWriteProbe().verify(url)
        } catch {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
            return
        }
        if didStartAccess {
            activeExportDirectoryAccessURL = url
        }
        exportDirectoryURL = url
        exportDirectoryDisplayName = url.path
    }

    private func updateWaitingExportDestinations() {
        guard let exportDirectoryURL else {
            return
        }
        for index in exportJobs.indices where exportJobs[index].status == .waiting {
            guard let video = project.videos.first(where: {
                $0.id == exportJobs[index].videoID
            }) else {
                continue
            }
            exportJobs[index].outputURL = availableOutputURL(
                for: video.fileName,
                in: exportDirectoryURL,
                excluding: exportJobs[index].id,
                codec: exportJobs[index].request.settings.codec
            )
        }
    }

    func enqueueVideos(selectedIDs: Set<UUID>) {
        guard !exportBatchHasStarted,
              let exportDirectoryURL else {
            return
        }
        let selectedVideos = ExportVideoSelection().videos(
            from: project.videos,
            selectedIDs: selectedIDs
        )
        guard !selectedVideos.isEmpty else {
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: exportDirectoryURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            exportDirectoryDisplayName = nil
            presentedError = PresentedError(
                title: AppStrings.text("ui.error.exportFolderMissingTitle"),
                message: AppStrings.text("ui.error.exportFolderMissingMessage")
            )
            return
        }
        do {
            try ensureExportDirectoryAccess(exportDirectoryURL)
        } catch {
            presentExportDirectoryAccessError(error)
            return
        }
        do {
            let estimate = try DiskSpaceEstimator().estimate(
                inputBytes: selectedVideos.map { video in
                    video.metadata.fileSizeBytes +
                        (video.timeResource.map(fileSize(of:)) ?? 0)
                },
                outputDirectory: exportDirectoryURL,
                outputCodec: project.exportSettings.codec
            )
            exportSpaceEstimate = estimate
            guard estimate.hasEnoughSpace else {
                presentedError = PresentedError(
                    title: AppStrings.text("ui.error.exportSpaceTitle"),
                    message: AppStrings.format(
                        "ui.error.exportSpaceMessage",
                        RunOverlayFormatters.fileSize(estimate.requiredBytes),
                        RunOverlayFormatters.fileSize(estimate.availableBytes)
                    )
                )
                return
            }
        } catch {
            presentedError = PresentedError(
                title: AppStrings.text("ui.error.exportSpaceCheckTitle"),
                message: error.localizedDescription
            )
            return
        }

        exportJobs.removeAll()
        for video in selectedVideos {
            let outputURL = availableOutputURL(
                for: video.fileName,
                in: exportDirectoryURL
            )
            exportJobs.append(
                ExportJob(
                    id: UUID(),
                    videoID: video.id,
                    fileName: video.fileName,
                    request: VideoExportRequest(
                        inputURL: resolveURL(for: video),
                        outputURL: outputURL,
                        videoStart: video.effectiveCapturedAt,
                        timeOffset: video.activityMatch.timeOffset,
                        overlay: video.overlayOverride ?? project.overlay,
                        activitySamples: previewSamples,
                        activityStart: project.activitySource?.timeRange?.start,
                        settings: project.exportSettings,
                        rotation: video.rotation
                    ),
                    outputURL: outputURL,
                    status: .waiting,
                    progress: 0
                )
            )
        }
        exportBatchHasStarted = true
        isExportQueuePresented = true
        scheduleExports()
    }

    func finishExportBatch() {
        guard exportBatchIsFinished else {
            return
        }
        exportBatchHasStarted = false
        restoreVideoSelectionAfterExport()
        isExportQueuePresented = false
        exportJobs.removeAll()
    }

    func dismissExportQueue() {
        if exportBatchIsFinished {
            finishExportBatch()
        } else {
            if exportBatchHasStarted {
                // 退出弹窗仅切回编辑视图；任务和顶部进度继续保留。
                restoreVideoSelectionAfterExport()
            }
            isExportQueuePresented = false
        }
    }

    func cancelExport(_ id: UUID) {
        guard let index = exportJobs.firstIndex(where: { $0.id == id }) else {
            return
        }
        if exportJobs[index].status == .waiting {
            exportJobs[index].status = .cancelled
            scheduleExports()
            completeExportBatchIfFinished()
        } else if exportJobs[index].status == .exporting {
            exportTasks[id]?.cancel()
            exporters[id]?.cancel()
        }
    }

    func cancelAllExports() {
        for job in exportJobs where job.status == .waiting {
            if let index = exportJobs.firstIndex(where: { $0.id == job.id }) {
                exportJobs[index].status = .cancelled
            }
        }
        for task in exportTasks.values {
            task.cancel()
        }
        for exporter in exporters.values {
            exporter.cancel()
        }
        scheduleExports()
        completeExportBatchIfFinished()
    }

    func resumeWaitingExports() {
        scheduleExports()
    }

    func retryExport(_ id: UUID) {
        guard
            !exportJobs.isEmpty,
            let index = exportJobs.firstIndex(where: { $0.id == id }),
            case .failed = exportJobs[index].status,
            let exportDirectoryURL,
            let video = project.videos.first(where: {
                $0.id == exportJobs[index].videoID
            })
        else {
            return
        }
        do {
            try ensureExportDirectoryAccess(exportDirectoryURL)
        } catch {
            presentExportDirectoryAccessError(error)
            return
        }
        exportJobs[index].outputURL = availableOutputURL(
            for: video.fileName,
            in: exportDirectoryURL,
            excluding: id,
            codec: exportJobs[index].request.settings.codec
        )
        exportJobs[index].progress = 0
        exportJobs[index].status = .waiting
        exportBatchHasStarted = true
        scheduleExports()
    }

    func revealExport(_ id: UUID) {
        guard let job = exportJobs.first(where: { $0.id == id }) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([job.outputURL])
    }

    func togglePlayback() {
        guard let video = selectedVideo,
              player.currentItem != nil else {
            return
        }
        if isPlaying || player.rate > 0 {
            pausePlayback()
            return
        }
        let frameInterval = 1 / max(video.metadata.frameRate, 1)
        if playbackTime >= video.metadata.durationSeconds - frameInterval {
            seek(to: 0)
        }
        player.play()
        isPlaying = true
    }

    func pausePlayback() {
        player.pause()
        isPlaying = false
    }

    func stepPlaybackFrame(_ direction: Int) {
        guard let video = selectedVideo,
              player.currentItem != nil else {
            return
        }
        pausePlayback()
        let frameInterval = 1 / max(video.metadata.frameRate, 1)
        seek(to: playbackTime + Double(direction) * frameInterval)
    }

    func skipPlayback(by seconds: TimeInterval) {
        guard selectedVideo != nil, player.currentItem != nil else {
            return
        }
        seek(to: playbackTime + seconds)
    }

    func seek(to seconds: TimeInterval) {
        let safeTime = max(0, min(seconds, selectedVideo?.metadata.durationSeconds ?? 0))
        let seekID = UUID()
        pendingPlaybackSeek = seekID
        playbackTime = safeTime
        player.seek(
            to: CMTime(seconds: safeTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero,
            completionHandler: { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.pendingPlaybackSeek == seekID else { return }
                    self.pendingPlaybackSeek = nil
                    self.playbackTime = safeTime
                }
            }
        )
    }

    func presentSaveSnapshotPanel() {
        guard !isSavingSnapshot,
              let video = selectedVideo,
              player.currentItem != nil else {
            return
        }
        pausePlayback()
        let pausedTime = player.currentTime()
        let capturedTime = VideoFrameSnapshotter.captureTime(
            playerTime: pausedTime.isNumeric ? pausedTime.seconds : nil,
            fallbackTime: playbackTime,
            duration: video.metadata.durationSeconds,
            frameRate: video.metadata.frameRate
        )
        playbackTime = capturedTime
        let videoURL = resolveURL(for: video)
        let panel = NSSavePanel()
        panel.title = AppStrings.text("ui.snapshot.saveTitle")
        panel.prompt = AppStrings.text("ui.snapshot.save")
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        if let exportDirectoryURL,
           FileManager.default.fileExists(atPath: exportDirectoryURL.path) {
            panel.directoryURL = exportDirectoryURL
        }
        let baseName = URL(fileURLWithPath: video.fileName)
            .deletingPathExtension().lastPathComponent
        let milliseconds = Int((capturedTime * 1_000).rounded())
        panel.nameFieldStringValue = String(
            format: "%@_%02d-%02d-%02d-%03d_RunOverlay.png",
            baseName,
            milliseconds / 3_600_000,
            (milliseconds / 60_000) % 60,
            (milliseconds / 1_000) % 60,
            milliseconds % 1_000
        )
        guard panel.runModal() == .OK, let outputURL = panel.url else {
            return
        }

        let request = VideoExportRequest(
            inputURL: videoURL,
            outputURL: outputURL,
            videoStart: video.effectiveCapturedAt,
            timeOffset: video.activityMatch.timeOffset,
            overlay: video.overlayOverride ?? project.overlay,
            activitySamples: previewSamples,
            activityStart: project.activitySource?.timeRange?.start,
            settings: project.exportSettings,
            rotation: video.rotation
        )
        let includeDataLayer = snapshotIncludesDataLayer
        isSavingSnapshot = true
        Task { [weak self] in
            let directory = outputURL.deletingLastPathComponent()
            let accessedDirectory = directory.startAccessingSecurityScopedResource()
            let accessedVideo = videoURL.startAccessingSecurityScopedResource()
            defer {
                if accessedDirectory { directory.stopAccessingSecurityScopedResource() }
                if accessedVideo { videoURL.stopAccessingSecurityScopedResource() }
                self?.isSavingSnapshot = false
            }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try VideoFrameSnapshotter().capture(
                        request,
                        at: capturedTime,
                        includeDataLayer: includeDataLayer
                    )
                }.value
                self?.presentedError = PresentedError(
                    title: AppStrings.text("ui.snapshot.saved"),
                    message: outputURL.path
                )
            } catch {
                self?.presentedError = PresentedError(
                    title: AppStrings.text("ui.snapshot.saveFailed"),
                    message: error.localizedDescription
                )
            }
        }
    }

    func presentCoverEditor() {
        guard let selectedVideo, canBrowseVideosDuringExport else { return }
        let position = playbackTime
        pausePlayback()
        pendingPlaybackSeek = nil
        coverEditorFrameTime = VideoFrameSnapshotter.captureTime(
            playerTime: nil,
            fallbackTime: position,
            duration: selectedVideo.metadata.durationSeconds,
            frameRate: selectedVideo.metadata.frameRate
        )
        coverEditorVideoID = selectedVideo.id
        isCoverEditorPresented = true
    }

    func clearCoverEditorFrameTime() {
        coverEditorFrameTime = nil
    }

    func cover(for videoID: UUID) -> VideoCover? {
        project.videos.first(where: { $0.id == videoID })?.cover
    }

    func updateCover(_ cover: VideoCover, for videoID: UUID) {
        guard canBrowseVideosDuringExport,
              let index = project.videos.firstIndex(where: { $0.id == videoID }),
              project.videos[index].cover != cover else {
            return
        }
        recordUndoCheckpoint("ui.history.cover")
        project.videos[index].cover = cover
        touchProject()
        scheduleCoverAutoSave()
    }

    func coverRequest(for videoID: UUID) -> VideoExportRequest? {
        guard let video = project.videos.first(where: { $0.id == videoID }) else {
            return nil
        }
        return VideoExportRequest(
            inputURL: resolveURL(for: video),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("\(videoID).png"),
            videoStart: video.effectiveCapturedAt,
            timeOffset: video.activityMatch.timeOffset,
            overlay: video.overlayOverride ?? project.overlay,
            activitySamples: previewSamples,
            activityStart: project.activitySource?.timeRange?.start,
            settings: project.exportSettings,
            rotation: video.rotation
        )
    }

    func resolveCoverResource(_ resource: CoverImageResource) -> URL {
        if let relativePath = resource.resourceRelativePath,
           let projectFileURL {
            let directory = projectFileURL.deletingLastPathComponent()
            let candidate = directory.appendingPathComponent(relativePath)
                .standardizedFileURL
            if candidate.path.hasPrefix(directory.standardizedFileURL.path + "/"),
               FileManager.default.isReadableFile(atPath: candidate.path) {
                return candidate
            }
        }
        if let bookmark = resource.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        return resource.fileURL
    }

    func coverResource(at url: URL) -> CoverImageResource {
        CoverImageResource(
            fileURL: url,
            bookmarkData: createBookmark(for: url)
        )
    }

    private func scheduleCoverAutoSave() {
        coverSaveTask?.cancel()
        coverSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.flushCoverAutoSave()
        }
    }

    @discardableResult
    func flushCoverAutoSave() -> Bool {
        coverSaveTask?.cancel()
        coverSaveTask = nil
        guard projectFileURL != nil ||
                project.videos.contains(where: { $0.cover != nil }) else {
            clearCoverAutoSavePointerForCurrentProject()
            return true
        }
        do {
            let destination = try projectFileURL ?? coverAutoSaveDestination()
            try ProjectFileCodec().save(project, to: destination)
            if projectFileURL == nil {
                UserDefaults.standard.set(
                    destination.path,
                    forKey: PreferencesKey.coverAutoSavePath
                )
                UserDefaults.standard.set(
                    selectedVideoID?.uuidString,
                    forKey: PreferencesKey.coverSelectedVideoID
                )
            } else {
                discardCoverAutoSaveForCurrentProject()
            }
            return true
        } catch {
            presentedError = PresentedError(
                title: AppStrings.text("ui.cover.saveFailed"),
                message: error.localizedDescription
            )
            return false
        }
    }

    private func coverAutoSaveDestination() throws -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileWriteUnknown)
        }
        let directory = appSupport
            .appendingPathComponent("RunOverlay", isDirectory: true)
            .appendingPathComponent("CoverDrafts", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("\(project.id.uuidString).runoverlay")
    }

    private func restoreUnsavedCoverProject() {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: PreferencesKey.coverAutoSavePath),
              let restored = try? projectCodec.load(from: URL(fileURLWithPath: path)),
              restored.videos.contains(where: { $0.cover != nil }) else {
            clearCoverAutoSavePointer()
            return
        }
        project = restored
        rebuildPreviewSamples()
        refreshMissingResources()
        let preferredID = defaults.string(forKey: PreferencesKey.coverSelectedVideoID)
            .flatMap(UUID.init(uuidString:))
        let videoID = restored.videos.contains(where: { $0.id == preferredID })
            ? preferredID : restored.videos.first?.id
        if let videoID {
            selectVideo(videoID)
        }
        for video in restored.videos {
            loadThumbnail(for: video)
        }
    }

    private func clearCoverAutoSavePointer() {
        UserDefaults.standard.removeObject(forKey: PreferencesKey.coverAutoSavePath)
        UserDefaults.standard.removeObject(forKey: PreferencesKey.coverSelectedVideoID)
    }

    /// 仅当自动保存指针指向当前项目草稿时才清除，避免误删其他未保存项目的恢复线索。
    private func clearCoverAutoSavePointerForCurrentProject() {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: PreferencesKey.coverAutoSavePath),
              let current = try? coverAutoSaveDestination() else { return }
        if URL(fileURLWithPath: path).standardizedFileURL.path ==
            current.standardizedFileURL.path {
            clearCoverAutoSavePointer()
        }
    }

    /// 当前项目已落盘或放弃时，删除其草稿并清理对应指针。
    private func discardCoverAutoSaveForCurrentProject() {
        try? FileManager.default.removeItem(at: coverAutoSaveDestination())
        clearCoverAutoSavePointerForCurrentProject()
    }

    func setTemplate(_ preset: OverlayTemplatePreset) {
        recordUndoCheckpoint("ui.history.template")
        let configuration = OverlayConfiguration.preset(preset)
        applyOverlayConfiguration(configuration)
        selectedOverlayElementID = configuration.elements.first?.id
        touchProject()
    }

    func saveOverlayDraft(named name: String, makeDefault: Bool) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }
        let draft = OverlayDraft(
            name: trimmedName,
            configuration: editingOverlayConfiguration
        )
        updateOverlayDraftLibrary(action: "ui.history.saveDraft") { library in
            library.add(draft, makeDefault: makeDefault)
        }
    }

    func applyOverlayDraft(_ id: UUID) {
        guard let draft = overlayDraftLibrary.draft(withID: id) else {
            return
        }
        recordUndoCheckpoint("ui.history.applyDraft")
        applyOverlayConfiguration(draft.configuration)
        selectedOverlayElementID = draft.configuration.elements.first?.id
        touchProject()
    }

    func setDefaultOverlayDraft(_ id: UUID) {
        updateOverlayDraftLibrary(action: "ui.history.defaultDraft") { library in
            _ = library.setDefault(id)
        }
    }

    func deleteOverlayDraft(_ id: UUID) {
        updateOverlayDraftLibrary(action: "ui.history.deleteDraft") { library in
            _ = library.remove(id)
        }
    }

    func presentExportOverlayDraftPanel(_ id: UUID) {
        guard let draft = overlayDraftLibrary.draft(withID: id) else {
            return
        }
        let panel = NSSavePanel()
        panel.title = AppStrings.text("ui.draft.exportPanelTitle")
        panel.prompt = AppStrings.text("ui.draft.export")
        panel.allowedContentTypes = [.runOverlayTemplate]
        panel.canCreateDirectories = true
        let safeName = draft.name
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = "\(safeName).\(OverlayDraftTransferService.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        let didStartAccess = url.deletingLastPathComponent()
            .startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.deletingLastPathComponent().stopAccessingSecurityScopedResource()
            }
        }
        do {
            try overlayDraftTransferService.save(draft, to: url)
            presentedError = PresentedError(
                title: AppStrings.text("ui.draft.exportSuccess"),
                message: url.path
            )
        } catch {
            presentedError = PresentedError(
                title: AppStrings.text("ui.draft.exportFailure"),
                message: error.localizedDescription
            )
        }
    }

    func presentImportOverlayDraftPanel() {
        let panel = NSOpenPanel()
        panel.title = AppStrings.text("ui.draft.importPanelTitle")
        panel.prompt = AppStrings.text("ui.draft.import")
        panel.allowedContentTypes = [.runOverlayTemplate]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else {
            return
        }
        let scopedURLs = panel.urls.filter {
            $0.startAccessingSecurityScopedResource()
        }
        defer {
            scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        }
        let files = overlayDraftTransferService.templateFiles(in: panel.urls)
        guard !files.isEmpty else {
            presentedError = PresentedError(
                title: AppStrings.text("ui.draft.importFailure"),
                message: AppStrings.text("ui.draft.noFilesInFolder")
            )
            return
        }
        var library = overlayDraftLibrary
        let before = editorState
        var importedCount = 0
        var existingCount = 0
        var failures: [String] = []
        for url in files {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let result = try overlayDraftTransferService.importTemplate(
                    from: url,
                    into: &library
                )
                switch result {
                case .imported:
                    importedCount += 1
                case .alreadyExists:
                    existingCount += 1
                }
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        if importedCount > 0 {
            do {
                try overlayDraftStore.save(library)
                overlayDraftLibrary = library
                recordHistory("ui.history.importDraft", before: before)
            } catch {
                presentedError = PresentedError(
                    title: AppStrings.text("ui.draft.importFailure"),
                    message: error.localizedDescription
                )
                return
            }
        }
        let summary = AppStrings.format(
            "ui.draft.batchImportSummary",
            importedCount,
            existingCount,
            failures.count
        )
        let message = ([summary] + failures).joined(separator: "\n")
        presentedError = PresentedError(
            title: AppStrings.text(
                importedCount > 0 ? "ui.draft.importSuccess"
                    : failures.isEmpty ? "ui.draft.alreadyExists" : "ui.draft.importFailure"
            ),
            message: message
        )
    }

    private func updateOverlayDraftLibrary(
        action: String,
        _ update: (inout OverlayDraftLibrary) -> Void
    ) {
        var library = overlayDraftLibrary
        update(&library)
        guard library != overlayDraftLibrary else {
            return
        }
        let before = editorState
        do {
            try overlayDraftStore.save(library)
            overlayDraftLibrary = library
            recordHistory(action, before: before)
        } catch {
            presentedError = PresentedError(
                title: AppStrings.text("ui.draft.saveFailure"),
                message: error.localizedDescription
            )
        }
    }

    func setOverlayEditingScope(_ scope: OverlayEditingScope) {
        guard overlayEditingScope != scope else { return }
        let before = editorState
        overlayEditingScope = scope
        selectedOverlayElementID = editingOverlayConfiguration.elements.first?.id
        recordHistory("ui.history.editingScope", before: before)
    }

    func selectOverlayElement(_ id: UUID) {
        selectedOverlayElementID = id
    }

    func setOverlayElementVisibility(_ id: UUID, isVisible: Bool) {
        mutateOverlay(action: "ui.history.layerVisibility") { configuration in
            guard let index = configuration.elements.firstIndex(where: { $0.id == id }) else {
                return
            }
            configuration.elements[index].isVisible = isVisible
        }
    }

    func toggleOverlayElement(_ kind: OverlayElementKind) {
        if let element = editingOverlayConfiguration.elements.first(where: {
            $0.kind == kind
        }) {
            setOverlayElementVisibility(element.id, isVisible: !element.isVisible)
            return
        }
        let element = editingOverlayConfiguration.newElement(for: kind)
        mutateOverlay(action: "ui.history.addLayer") { $0.elements.append(element) }
    }

    func ensureOverlayElement(_ kind: OverlayElementKind) -> UUID {
        if let existing = editingOverlayConfiguration.elements.first(where: { $0.kind == kind }) {
            selectedOverlayElementID = existing.id
            return existing.id
        }
        var element = editingOverlayConfiguration.newElement(for: kind)
        element.isVisible = false
        mutateOverlay(action: "ui.history.addLayer") { $0.elements.append(element) }
        selectedOverlayElementID = element.id
        return element.id
    }

    func setOverlayElementFrame(_ id: UUID, frame: NormalizedRect) {
        mutateOverlay(action: "ui.history.layerFrame") { configuration in
            guard let index = configuration.elements.firstIndex(where: { $0.id == id }) else {
                return
            }
            configuration.elements[index].frame = constrained(frame)
        }
        selectedOverlayElementID = id
    }

    func setOverlayElementOpacity(_ id: UUID, opacity: Double) {
        mutateOverlay(action: "ui.history.layerOpacity") { configuration in
            guard let index = configuration.elements.firstIndex(where: { $0.id == id }) else {
                return
            }
            configuration.elements[index].opacity = min(max(opacity, 0), 1)
        }
    }

    func setOverlayElementBackgroundOpacity(_ id: UUID, opacity: Double) {
        mutateOverlay(action: "ui.history.layerBackground") { configuration in
            guard let index = configuration.elements.firstIndex(where: { $0.id == id }) else {
                return
            }
            configuration.elements[index].backgroundOpacity = min(max(opacity, 0), 1)
        }
    }

    func setOverlayElementTextScale(_ id: UUID, scale: Double) {
        mutateOverlay(action: "ui.history.layerTextSize") { configuration in
            guard let index = configuration.elements.firstIndex(where: { $0.id == id }) else {
                return
            }
            configuration.elements[index].textScale = min(max(scale, 0.5), 2)
        }
    }

    func setOverlayElementMeasurementUnit(_ id: UUID, unit: OverlayMeasurementUnit) {
        guard let element = editingOverlayConfiguration.elements.first(where: { $0.id == id }),
              element.kind.supportedMeasurementUnits.contains(unit),
              element.effectiveMeasurementUnit != unit else {
            return
        }
        mutateOverlay(action: "ui.history.layerUnit") { configuration in
            guard let index = configuration.elements.firstIndex(where: { $0.id == id }) else {
                return
            }
            configuration.elements[index].measurementUnit = unit
        }
    }

    func setOverlayElementClockDisplay(_ id: UUID, display: OverlayClockDisplay) {
        guard let element = editingOverlayConfiguration.elements.first(where: { $0.id == id }),
              element.kind == .clockTime,
              element.clockDisplay != display else {
            return
        }
        mutateOverlay(action: "ui.history.layerClockDisplay") { configuration in
            guard let index = configuration.elements.firstIndex(where: { $0.id == id }) else {
                return
            }
            configuration.elements[index].clockDisplay = display
        }
    }

    func setOverlayElementDurationDisplay(_ id: UUID, display: OverlayDurationDisplay) {
        guard let element = editingOverlayConfiguration.elements.first(where: { $0.id == id }),
              element.kind == .elapsedTime,
              element.durationDisplay != display else {
            return
        }
        mutateOverlay(action: "ui.history.layerDurationDisplay") { configuration in
            guard let index = configuration.elements.firstIndex(where: { $0.id == id }) else {
                return
            }
            configuration.elements[index].durationDisplay = display
        }
    }

    func moveOverlayElement(_ id: UUID, by delta: CGSize, canvasSize: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return
        }
        mutateOverlay(action: "ui.history.moveLayer") { configuration in
            guard let index = configuration.elements.firstIndex(where: { $0.id == id }) else {
                return
            }
            var frame = configuration.elements[index].frame
            frame.x += delta.width / canvasSize.width
            frame.y += delta.height / canvasSize.height
            configuration.elements[index].frame = constrained(frame)
        }
        selectedOverlayElementID = id
    }

    func resizeOverlayElement(
        _ id: UUID,
        by delta: CGSize,
        canvasSize: CGSize,
        anchor: CGPoint = CGPoint(x: 1, y: 1)
    ) {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return
        }
        mutateOverlay(action: "ui.history.resizeLayer") { configuration in
            guard let index = configuration.elements.firstIndex(where: { $0.id == id }) else {
                return
            }
            var frame = configuration.elements[index].frame
            let minimumWidth = 0.08
            let minimumHeight = 0.06
            let maximumWidth = 0.8
            let maximumHeight = 0.8
            let oldWidth = frame.width
            let oldHeight = frame.height
            frame.width = min(
                max(oldWidth + delta.width * anchor.x / canvasSize.width, minimumWidth),
                maximumWidth
            )
            frame.height = min(
                max(oldHeight + delta.height * anchor.y / canvasSize.height, minimumHeight),
                maximumHeight
            )
            if anchor.x < 0 {
                frame.x += oldWidth - frame.width
            }
            if anchor.y < 0 {
                frame.y += oldHeight - frame.height
            }
            configuration.elements[index].frame = constrained(frame)
        }
        selectedOverlayElementID = id
    }

    func setOverlayAccentHex(_ hex: String) {
        mutateOverlay(action: "ui.history.accent") { $0.accentHex = hex }
    }

    func resetCurrentVideoOverlay() {
        guard
            overlayEditingScope == .currentVideo,
            let selectedVideoID,
            let index = project.videos.firstIndex(where: { $0.id == selectedVideoID }),
            project.videos[index].overlayOverride != nil
        else {
            return
        }
        recordUndoCheckpoint("ui.history.restoreOverlay")
        project.videos[index].overlayOverride = nil
        selectedOverlayElementID = project.overlay.elements.first?.id
        touchProject()
    }

    func undo() {
        guard canEditHistory else { return }
        if let previous = editHistory.undo(current: editorState) {
            restoreState(previous)
        }
    }

    func redo() {
        guard canEditHistory else { return }
        if let next = editHistory.redo(current: editorState) {
            restoreState(next)
        }
    }

    func presentSaveProjectPanel() {
        if let projectFileURL {
            saveProject(to: projectFileURL)
            return
        }

        let panel = NSSavePanel()
        panel.title = AppStrings.text("ui.panel.saveProjectTitle")
        panel.prompt = AppStrings.text("ui.panel.saveProjectPrompt")
        panel.allowedContentTypes = [.runOverlayProject]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(project.name).runoverlay"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        saveProject(to: url)
    }

    func presentOpenProjectPanel() {
        let panel = NSOpenPanel()
        panel.title = AppStrings.text("ui.panel.openProjectTitle")
        panel.prompt = AppStrings.text("ui.panel.openProjectPrompt")
        panel.allowedContentTypes = [.runOverlayProject]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        openProject(at: url)
    }

    func openProject(at url: URL) {
        guard !exportBatchHasStarted else {
            presentedError = PresentedError(
                title: AppStrings.text("ui.error.projectChangeDuringExportTitle"),
                message: AppStrings.text("ui.error.projectChangeDuringExportMessage")
            )
            return
        }
        isCoverEditorPresented = false
        coverEditorVideoID = nil
        coverEditorFrameTime = nil
        let didStartAccess = url.startAccessingSecurityScopedResource()
        if coverSaveTask != nil, !flushCoverAutoSave() {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
            return
        }
        do {
            let openedProject = try projectCodec.load(from: url)
            releaseActiveProjectFileAccess()
            if didStartAccess { activeProjectFileAccessURL = url }
            pausePlayback()
            coverSaveTask?.cancel()
            releaseActiveVideoAccess()
            releaseActiveTimeResourceAccess()
            player.replaceCurrentItem(with: nil)
            project = openedProject
            discardCoverAutoSaveForCurrentProject()
            videoThumbnails.removeAll()
            exportVideoSelection = nil
            rebuildPreviewSamples()
            clearHistory()
            projectFileURL = url
            resolvePackagedResources(relativeTo: url.deletingLastPathComponent())
            refreshMissingResources()
            selectedVideoID = project.videos.first?.id
            if let selectedVideoID {
                selectVideo(selectedVideoID)
            }
            for video in project.videos {
                loadThumbnail(for: video)
            }
        } catch {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
            presentedError = PresentedError(
                title: AppStrings.text("ui.error.openProjectTitle"),
                message: error.localizedDescription
            )
        }
    }

    func presentRelinkMissingResourcesPanel() {
        let panel = NSOpenPanel()
        panel.title = AppStrings.text("ui.panel.relinkTitle")
        panel.prompt = AppStrings.text("ui.panel.scanRelink")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let directory = panel.url else {
            return
        }

        let didStartAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        let candidates = enumerateMediaFiles(in: directory)
        guard !candidates.isEmpty else {
            presentedError = PresentedError(
                title: AppStrings.text("ui.error.noMediaTitle"),
                message: AppStrings.text("ui.error.noMediaMessage")
            )
            return
        }
        let before = editorState

        var candidateGroups: [String: [URL]] = [:]
        for candidate in candidates {
            candidateGroups[candidate.lastPathComponent.lowercased(), default: []]
                .append(candidate)
        }

        for index in project.videos.indices {
            let videoURL = resolveURL(for: project.videos[index])
            if !FileManager.default.isReadableFile(atPath: videoURL.path) {
                let key = project.videos[index].fileName.lowercased()
                if var matches = candidateGroups[key], !matches.isEmpty {
                    let candidate = matches.removeFirst()
                    candidateGroups[key] = matches
                    project.videos[index].fileURL = candidate
                    project.videos[index].bookmarkData = createBookmark(for: candidate)
                    project.videos[index].resourceRelativePath = nil
                }
            }

            let existingSidecarURL = project.videos[index].timeResource.map {
                resolveURL(for: $0)
            }
            let needsSidecar = project.videos[index].timeResource == nil ||
                (existingSidecarURL.map {
                    !FileManager.default.isReadableFile(atPath: $0.path)
            } ?? false)
            if needsSidecar {
                let matchingKey = sidecarNames(for: project.videos[index].fileName)
                    .first { !(candidateGroups[$0] ?? []).isEmpty }
                if let matchingKey, var matches = candidateGroups[matchingKey], !matches.isEmpty {
                    let sidecar = matches.removeFirst()
                    candidateGroups[matchingKey] = matches
                    project.videos[index].timeResource = makeTimeResource(from: sidecar)
                }
            }
        }

        if let source = project.activitySource,
           !FileManager.default.isReadableFile(atPath: resolveActivityURL(source).path) {
            let key = source.fileName.lowercased()
            if let candidate = candidateGroups[key]?.first,
               let parsed = try? ActivityParser().parse(from: candidate) {
                project.activitySource?.fileURL = candidate
                project.activitySource?.bookmarkData = createBookmark(for: candidate)
                project.activitySource?.resourceRelativePath = nil
                project.activitySource?.timeRange = parsed.timeRange
                project.activitySource?.sampleCount = parsed.samples.count
                project.activitySource?.availableChannels = parsed.availableChannels
                project.activitySamples = parsed.samples
                rebuildPreviewSamples()
                rematchAllVideos()
                isActivityResourceMissing = false
            }
        }

        refreshMissingResources()
        rematchAllVideos()
        for video in project.videos {
            if !missingResourceVideoIDs.contains(video.id) {
                loadThumbnail(for: video)
            }
        }
        touchProject()
        recordHistory("ui.history.relink", before: before)
    }

    func packageProject() {
        guard !isPackagingProject else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = AppStrings.text("ui.panel.packageTitle")
        panel.prompt = AppStrings.text("ui.panel.saveCopy")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else {
            return
        }

        let safeName = project.name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let packageURL = parent.appendingPathComponent(
            "\(safeName).runoverlay-package",
            isDirectory: true
        )
        var resources: [URL: URL] = [:]
        var scopedURLs: [URL] = [parent]

        if let source = project.activitySource {
            let url = resolveActivityURL(source)
            resources[source.fileURL.standardizedFileURL] = url
            scopedURLs.append(url)
        }
        for video in project.videos {
            let url = resolveURL(for: video)
            resources[video.fileURL.standardizedFileURL] = url
            scopedURLs.append(url)
            if let sidecar = video.timeResource {
                let sidecarURL = resolveURL(for: sidecar)
                resources[sidecar.fileURL.standardizedFileURL] = sidecarURL
                scopedURLs.append(sidecarURL)
            }
            if let cover = video.cover {
                if case let .image(source) = cover.source {
                    let sourceURL = resolveCoverResource(source)
                    resources[source.fileURL.standardizedFileURL] = sourceURL
                    scopedURLs.append(sourceURL)
                }
                if let exported = cover.exportedImage {
                    let exportedURL = resolveCoverResource(exported)
                    resources[exported.fileURL.standardizedFileURL] = exportedURL
                    scopedURLs.append(exportedURL)
                }
            }
        }
        let startedURLs = scopedURLs.filter {
            $0.startAccessingSecurityScopedResource()
        }
        isPackagingProject = true
        let projectSnapshot = project
        let resourceSnapshot = resources

        Task {
            defer {
                startedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
                isPackagingProject = false
            }

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ProjectPackageService().packageProject(
                        projectSnapshot,
                        to: packageURL,
                        resolveURL: { url, _ in
                            resourceSnapshot[url.standardizedFileURL] ?? url
                        }
                    )
                }.value
                presentedError = PresentedError(
                    title: AppStrings.text(
                        result.missingFiles.isEmpty
                            ? "ui.error.packageSuccessTitle"
                            : "ui.error.packagePartialTitle"
                    ),
                    message: AppStrings.format(
                        "ui.error.packageResult",
                        result.projectURL.path,
                        result.copiedFileCount,
                        RunOverlayFormatters.fileSize(result.totalBytes)
                    ) + (result.missingFiles.isEmpty
                        ? ""
                        : AppStrings.format(
                            "ui.error.packageMissing",
                            result.missingFiles.joined(separator: ", ")
                        ))
                )
            } catch {
                presentedError = PresentedError(
                    title: AppStrings.text("ui.error.packageFailureTitle"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func saveProject(to url: URL) {
        do {
            touchProject()
            try projectCodec.save(project, to: url)
            coverSaveTask?.cancel()
            coverSaveTask = nil
            projectFileURL = url
            discardCoverAutoSaveForCurrentProject()
        } catch {
            presentedError = PresentedError(
                title: AppStrings.text("ui.error.saveProjectTitle"),
                message: error.localizedDescription
            )
        }
    }

    private func resolveURL(for video: VideoItem) -> URL {
        if let relativePath = video.resourceRelativePath,
           let projectFileURL {
            let packageDirectory = projectFileURL.deletingLastPathComponent()
            let packagedURL = packageDirectory
                .appendingPathComponent(relativePath)
                .standardizedFileURL
            if packagedURL.path.hasPrefix(packageDirectory.standardizedFileURL.path + "/"),
               FileManager.default.isReadableFile(atPath: packagedURL.path) {
                return packagedURL
            }
        }
        guard let bookmarkData = video.bookmarkData else {
            return video.fileURL
        }

        var isStale = false
        do {
            return try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            return video.fileURL
        }
    }

    private func resolveURL(for resource: VideoTimeResource) -> URL {
        if let relativePath = resource.resourceRelativePath,
           let projectFileURL {
            let packageDirectory = projectFileURL.deletingLastPathComponent()
            let packagedURL = packageDirectory
                .appendingPathComponent(relativePath)
                .standardizedFileURL
            if packagedURL.path.hasPrefix(packageDirectory.standardizedFileURL.path + "/"),
               FileManager.default.isReadableFile(atPath: packagedURL.path) {
                return packagedURL
            }
        }
        if let bookmarkData = resource.bookmarkData {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return resolved
            }
        }
        return resource.fileURL
    }

    private func fileSize(of resource: VideoTimeResource) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: resolveURL(for: resource).path
        )
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func touchProject() {
        project.updatedAt = Date()
        commitPendingEdit()
    }

    private func mutateOverlay(
        action: String = "ui.history.overlay",
        _ mutation: (inout OverlayConfiguration) -> Void
    ) {
        recordUndoCheckpoint(action)
        var configuration = editingOverlayConfiguration
        mutation(&configuration)
        applyOverlayConfiguration(configuration)
        touchProject()
    }

    private func applyOverlayConfiguration(_ configuration: OverlayConfiguration) {
        if overlayEditingScope == .currentVideo,
           let selectedVideoID,
           let index = project.videos.firstIndex(where: { $0.id == selectedVideoID }) {
            project.videos[index].overlayOverride = configuration
        } else {
            project.overlay = configuration
        }
    }

    private func constrained(_ frame: NormalizedRect) -> NormalizedRect {
        let width = min(max(frame.width, 0.08), 0.8)
        let height = min(max(frame.height, 0.06), 0.8)
        return NormalizedRect(
            x: min(max(frame.x, 0), 1 - width),
            y: min(max(frame.y, 0), 1 - height),
            width: width,
            height: height
        )
    }

    private var editorState: EditorState {
        EditorState(
            project: project,
            drafts: overlayDraftLibrary,
            selectedVideoID: selectedVideoID,
            selectedElementID: selectedOverlayElementID,
            exportVideoSelection: exportVideoSelection,
            editingScope: overlayEditingScope,
            exportDirectoryURL: exportDirectoryURL,
            projectFileURL: projectFileURL,
            language: selectedLanguage
        )
    }

    private func recordUndoCheckpoint(_ action: String = "ui.history.edit") {
        guard pendingEdit == nil else { return }
        pendingEdit = (action, editorState)
    }

    private func recordHistory(_ action: String, before: EditorState) {
        let after = editorState
        var oldProject = before.project
        oldProject.updatedAt = after.project.updatedAt
        let comparableBefore = EditorState(
            project: oldProject,
            drafts: before.drafts,
            selectedVideoID: before.selectedVideoID,
            selectedElementID: before.selectedElementID,
            exportVideoSelection: before.exportVideoSelection,
            editingScope: before.editingScope,
            exportDirectoryURL: before.exportDirectoryURL,
            projectFileURL: before.projectFileURL,
            language: before.language
        )
        guard comparableBefore != after else { return }
        let continuousActions: Set<String> = [
            "ui.history.timeOffset", "ui.history.videoSelection",
            "ui.history.layerFrame", "ui.history.layerOpacity",
            "ui.history.layerBackground", "ui.history.layerTextSize"
        ]
        let now = Date()
        if continuousActions.contains(action),
           let previous = lastContinuousEdit,
           previous.action == action,
           now.timeIntervalSince(previous.at) < 0.8,
           editHistory.canUndo,
           !editHistory.canRedo {
            editHistory.replaceLatestUndo(
                action: action,
                before: previous.before,
                after: after
            )
            lastContinuousEdit = (action, now, previous.before)
        } else {
            editHistory.record(action: action, before: before, after: after)
            lastContinuousEdit = continuousActions.contains(action)
                ? (action, now, before) : nil
        }
    }

    private func commitPendingEdit() {
        guard let pendingEdit else { return }
        self.pendingEdit = nil
        recordHistory(pendingEdit.action, before: pendingEdit.before)
    }

    private func clearHistory() {
        pendingEdit = nil
        lastContinuousEdit = nil
        editHistory.clear()
    }

    private func restoreState(_ state: EditorState) {
        pendingEdit = nil
        lastContinuousEdit = nil
        let coverChanged = project.videos.map(\.cover) !=
            state.project.videos.map(\.cover)
        let previousVideo = selectedVideo
        let previousTime = playbackTime
        let wasPlaying = isPlaying
        if projectFileURL != state.projectFileURL {
            releaseActiveProjectFileAccess()
            projectFileURL = state.projectFileURL
            if let url = state.projectFileURL,
               url.startAccessingSecurityScopedResource() {
                activeProjectFileAccessURL = url
            }
        }
        project = state.project
        if overlayDraftLibrary != state.drafts {
            do {
                try overlayDraftStore.save(state.drafts)
                overlayDraftLibrary = state.drafts
            } catch {
                presentedError = PresentedError(
                    title: AppStrings.text("ui.draft.saveFailure"),
                    message: error.localizedDescription
                )
            }
        }
        if selectedLanguage != state.language {
            RunOverlayLocalization.language = state.language
            selectedLanguage = state.language
        }
        if exportDirectoryURL != state.exportDirectoryURL {
            if let url = state.exportDirectoryURL {
                setExportDirectory(url, recordsHistory: false)
            } else {
                releaseExportDirectoryAccess()
                exportDirectoryURL = nil
                exportDirectoryDisplayName = nil
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: PreferencesKey.exportDirectoryPath)
                defaults.removeObject(forKey: PreferencesKey.exportDirectoryBookmark)
            }
        }
        overlayEditingScope = state.editingScope
        selectedOverlayElementID = state.selectedElementID
        exportVideoSelection = state.exportVideoSelection?.intersection(
            Set(project.videos.map(\.id))
        )
        rebuildPreviewSamples()
        refreshMissingResources()
        videoThumbnails = videoThumbnails.filter { id, _ in
            guard let video = project.videos.first(where: { $0.id == id }) else {
                return false
            }
            return previousVideo?.id != id ||
                previousVideo?.fileURL == video.fileURL
        }
        let selectedID = state.selectedVideoID.flatMap { id in
            project.videos.contains { $0.id == id } ? id : nil
        }
        let nextVideo = selectedID.flatMap { id in
            project.videos.first(where: { $0.id == id })
        }
        if previousVideo?.id != selectedID ||
            previousVideo?.fileURL != nextVideo?.fileURL ||
            previousVideo?.bookmarkData != nextVideo?.bookmarkData ||
            player.currentItem == nil && nextVideo != nil {
            pausePlayback()
            releaseActiveVideoAccess()
            releaseActiveTimeResourceAccess()
            player.replaceCurrentItem(with: nil)
            selectedVideoID = nil
            if let selectedID {
                selectVideo(selectedID, preservesElementSelection: true)
                seek(to: previousVideo?.id == selectedID ? previousTime : 0)
            } else {
                playbackTime = 0
            }
        } else {
            selectedVideoID = selectedID
            if wasPlaying && player.currentItem != nil {
                player.play()
                isPlaying = true
            }
        }
        if let selectedElementID = state.selectedElementID,
           editingOverlayConfiguration.elements.contains(where: {
               $0.id == selectedElementID
           }) {
            selectedOverlayElementID = selectedElementID
        } else {
            selectedOverlayElementID = nil
        }
        for video in project.videos where videoThumbnails[video.id] == nil {
            loadThumbnail(for: video)
        }
        if coverChanged {
            scheduleCoverAutoSave()
        }
    }

    private func rematchAllVideos() {
        guard let activityRange = project.activitySource?.timeRange else {
            project.videos = project.videos.map { video in
                var updated = video
                updated.activityMatch = ActivityMatch(status: .pending)
                return updated
            }
            return
        }

        project.videos = project.videos.map { video in
            var updated = video
            updated.activityMatch = activityMatcher.match(
                videoStart: video.effectiveCapturedAt,
                duration: video.metadata.durationSeconds,
                activityRange: activityRange,
                timeOffset: video.activityMatch.timeOffset,
                calibrationMethod: video.activityMatch.calibrationMethod
            )
            return updated
        }
    }

    private func rebuildPreviewSamples() {
        previewSamples = activityTimeline.smoothed(
            samples: project.activitySamples,
            level: project.smoothingLevel
        )
        activityProgressCalculator = ActivityProgressCalculator(
            samples: previewSamples
        )
        elevationProfile = ElevationProfile(samples: previewSamples)
    }

    private func scheduleExports() {
        guard exportDirectoryURL != nil else {
            return
        }
        let concurrency = project.exportSettings.parallelTaskCount
        while activeExportIDs.count < concurrency,
              let job = exportJobs.first(where: { $0.status == .waiting }) {
            activeExportIDs.insert(job.id)
            if let index = exportJobs.firstIndex(where: { $0.id == job.id }) {
                exportJobs[index].status = .exporting
            }
            exportTasks[job.id] = Task { @MainActor [weak self] in
                await self?.runExport(job.id)
            }
        }
        isExporting = !activeExportIDs.isEmpty
        if isExporting {
            acquireSleepAssertion()
        } else {
            releaseSleepAssertion()
        }
        if activeExportIDs.isEmpty &&
            !exportJobs.contains(where: { $0.status == .waiting }) {
            releaseExportDirectoryAccess()
        }
    }

    private func ensureExportDirectoryAccess(_ url: URL) throws {
        // 若原先的授权仍有效，继续沿用，不要关闭后再尝试恢复旧书签。
        if activeExportDirectoryAccessURL?.standardizedFileURL == url.standardizedFileURL {
            try ExportDirectoryWriteProbe().verify(url)
            return
        }
        let didStartAccess = url.startAccessingSecurityScopedResource()
        do {
            try ExportDirectoryWriteProbe().verify(url)
        } catch {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
            throw error
        }
        if didStartAccess {
            activeExportDirectoryAccessURL = url
        }
    }

    private func presentExportDirectoryAccessError(_ error: Error) {
        presentedError = PresentedError(
            title: AppStrings.text("ui.error.exportFolderPermissionTitle"),
            message: AppStrings.format(
                "ui.error.exportFolderPermissionMessage",
                error.localizedDescription
            )
        )
    }

    private func releaseExportDirectoryAccess() {
        activeExportDirectoryAccessURL?.stopAccessingSecurityScopedResource()
        activeExportDirectoryAccessURL = nil
    }

    private func acquireSleepAssertion() {
        guard sleepAssertionID == 0 else {
            return
        }
        let reason = AppStrings.text("ui.export.preventSleepReason") as CFString
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &sleepAssertionID
        )
    }

    private func releaseSleepAssertion() {
        guard sleepAssertionID != 0 else {
            return
        }
        IOPMAssertionRelease(sleepAssertionID)
        sleepAssertionID = 0
    }

    private func refreshMissingResources() {
        let status = ProjectResourceStatus(
            project: project,
            videoURL: { resolveURL(for: $0) },
            timeResourceURL: { resolveURL(for: $0) },
            activityURL: { resolveActivityURL($0) },
            isReadable: { url in
                let didStartAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                return FileManager.default.isReadableFile(atPath: url.path)
            }
        )
        missingResourceVideoIDs = status.missingVideoIDs
        missingVideoTimeResourceIDs = status.missingTimeResourceVideoIDs
        isActivityResourceMissing = status.isActivitySourceMissing
    }

    private func resolvePackagedResources(relativeTo directory: URL) {
        let relocation = ResourceRelocator().resolveProjectResources(
            project,
            relativeTo: directory
        )
        if let activityURL = relocation.activityURL {
            project.activitySource?.fileURL = activityURL
            project.activitySource?.bookmarkData = createBookmark(for: activityURL)
        }
        for index in project.videos.indices {
            let id = project.videos[index].id
            if let url = relocation.videoURLs[project.videos[index].id] {
                project.videos[index].fileURL = url
                project.videos[index].bookmarkData = createBookmark(for: url)
            }
            if let url = relocation.sidecarURLs[project.videos[index].id] {
                project.videos[index].timeResource?.fileURL = url
                project.videos[index].timeResource?.bookmarkData = createBookmark(for: url)
            }
            if let url = relocation.coverSourceURLs[id],
               case var .image(source)? = project.videos[index].cover?.source {
                source.fileURL = url
                source.bookmarkData = createBookmark(for: url)
                project.videos[index].cover?.source = .image(source)
            }
            if let url = relocation.coverExportURLs[id] {
                project.videos[index].cover?.exportedImage?.fileURL = url
                project.videos[index].cover?.exportedImage?.bookmarkData =
                    createBookmark(for: url)
            }
        }
        rematchAllVideos()
        refreshMissingResources()
        for video in project.videos {
            if !missingResourceVideoIDs.contains(video.id) {
                loadThumbnail(for: video)
            }
        }
    }

    private func resolveActivityURL(_ source: ActivitySource) -> URL {
        if let relativePath = source.resourceRelativePath,
           let projectFileURL {
            let packageDirectory = projectFileURL.deletingLastPathComponent()
            let packagedURL = packageDirectory
                .appendingPathComponent(relativePath)
                .standardizedFileURL
            if packagedURL.path.hasPrefix(packageDirectory.standardizedFileURL.path + "/"),
               FileManager.default.isReadableFile(atPath: packagedURL.path) {
                return packagedURL
            }
        }
        if let bookmarkData = source.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        return source.fileURL
    }

    private func createBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func enumerateMediaFiles(in directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        let supportedExtensions: Set<String> = [
            "mp4", "mov", "m4v", "fit", "gpx"
        ]
        return enumerator.compactMap { $0 as? URL }.filter {
            supportedExtensions.contains($0.pathExtension.lowercased()) ||
                VideoTimeResourceReader.supportedExtensions.contains(
                    $0.pathExtension.lowercased()
                )
        }
    }

    private func attachTimeResourcesToExistingVideos(
        _ resources: [URL: VideoTimeResource]
    ) {
        guard !resources.isEmpty else {
            return
        }
        let before = editorState
        var didChange = false
        for index in project.videos.indices {
            guard let resource = resources[
                project.videos[index].fileURL
                    .resolvingSymlinksInPath()
                    .standardizedFileURL
            ] else {
                continue
            }
            project.videos[index].timeResource = resource
            didChange = true
        }
        if didChange {
            rematchAllVideos()
            touchProject()
            recordHistory("ui.history.relink", before: before)
        }
    }

    private func makeTimeResource(from url: URL) -> VideoTimeResource {
        VideoTimeResource(
            fileName: url.lastPathComponent,
            fileURL: url,
            bookmarkData: createBookmark(for: url),
            capturedAt: VideoTimeResourceReader().capturedAt(from: url)
        )
    }

    private func matchingTimeResources(for videoURLs: [URL]) -> [URL: VideoTimeResource] {
        let fileManager = FileManager.default
        var matches: [URL: VideoTimeResource] = [:]
        for videoURL in videoURLs {
            let candidates = sidecarURLs(for: videoURL).filter {
                fileManager.isReadableFile(atPath: $0.path)
            }
            guard candidates.count == 1, let sidecarURL = candidates.first else {
                continue
            }
            matches[videoURL.resolvingSymlinksInPath().standardizedFileURL] =
                makeTimeResource(from: sidecarURL)
        }
        return matches
    }

    private func sidecarURLs(for videoURL: URL) -> [URL] {
        let directory = videoURL.deletingLastPathComponent()
        let names = Set(sidecarNames(for: videoURL.lastPathComponent))
        return (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))?.filter {
            names.contains($0.lastPathComponent.lowercased()) &&
                VideoTimeResourceReader.supportedExtensions.contains(
                    $0.pathExtension.lowercased()
                )
        }.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        } ?? []
    }

    private func sidecarNames(for videoName: String) -> [String] {
        VideoTimeResourceReader().candidateFileNames(forVideoName: videoName)
    }

    private func loadThumbnail(for video: VideoItem) {
        guard videoThumbnails[video.id] == nil,
              thumbnailLoadingIDs.insert(video.id).inserted else {
            return
        }
        let url = resolveURL(for: video)
        let didStartAccess = url.startAccessingSecurityScopedResource()
        Task { [weak self] in
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
                self?.thumbnailLoadingIDs.remove(video.id)
            }
            let imageResult = await Task.detached(priority: .utility) {
                try VideoThumbnailReader().read(from: url)
            }.result
            guard case let .success(image) = imageResult else {
                return
            }
            guard self?.project.videos.contains(where: { $0.id == video.id }) == true else {
                return
            }
            self?.videoThumbnails[video.id] = NSImage(
                cgImage: image,
                size: NSSize(width: image.width, height: image.height)
            )
        }
    }

    private func runExport(_ jobID: UUID) async {
        guard
            let jobIndex = exportJobs.firstIndex(where: { $0.id == jobID }),
            let video = project.videos.first(where: {
                $0.id == exportJobs[jobIndex].videoID
            })
        else {
            finishExport(
                jobID,
                status: .failed(AppStrings.text("ui.error.videoProjectMissing"))
            )
            return
        }

        let job = exportJobs[jobIndex]
        let inputURL = job.request.inputURL
        do {
            try ensureExportDirectoryAccess(job.outputURL.deletingLastPathComponent())
        } catch {
            finishExport(
                jobID,
                status: .failed(AppStrings.format(
                    "ui.error.exportFolderPermissionMessage",
                    error.localizedDescription
                ))
            )
            return
        }
        let didStartAccess = inputURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                inputURL.stopAccessingSecurityScopedResource()
            }
            exporters[jobID] = nil
            exportTasks[jobID] = nil
        }

        do {
            try Task.checkCancellation()
            guard FileManager.default.isReadableFile(atPath: inputURL.path) else {
                throw CocoaError(.fileReadNoPermission)
            }
            try FileManager.default.createDirectory(
                at: job.outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let availableBytes = try FileManager.default.attributesOfFileSystem(
                forPath: job.outputURL.deletingLastPathComponent().path
            )[.systemFreeSize] as? NSNumber
            let estimatedBytes = max(
                Int64(256 * 1_024 * 1_024),
                video.metadata.fileSizeBytes / 2
            )
            if let availableBytes, availableBytes.int64Value < estimatedBytes {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            var request = job.request
            request.outputURL = job.outputURL
            let exporter = VideoExporter()
            exporters[jobID] = exporter
            try Task.checkCancellation()
            try await exporter.export(request) { [weak self] progress in
                await MainActor.run {
                    self?.updateExportProgress(jobID, progress: progress)
                }
            }
            finishExport(jobID, status: .completed)
        } catch {
            if error is CancellationError ||
                (error as? VideoExporterError) == .cancelled {
                finishExport(jobID, status: .cancelled)
            } else {
                finishExport(jobID, status: .failed(error.localizedDescription))
            }
        }
    }

    private func updateExportProgress(_ id: UUID, progress: Double) {
        guard let index = exportJobs.firstIndex(where: { $0.id == id }) else {
            return
        }
        exportJobs[index].progress = min(max(progress, 0), 1)
    }

    private func finishExport(_ id: UUID, status: ExportJobStatus) {
        if let index = exportJobs.firstIndex(where: { $0.id == id }) {
            exportJobs[index].status = status
            if status == .completed {
                exportJobs[index].progress = 1
            }
        }
        activeExportIDs.remove(id)
        exportTasks[id] = nil
        exporters[id] = nil
        scheduleExports()
        completeExportBatchIfFinished()
    }

    private func completeExportBatchIfFinished() {
        guard exportBatchHasStarted, exportBatchIsFinished else { return }
        exportBatchHasStarted = false
        restoreVideoSelectionAfterExport()
        if !ExportQueueInteractionPolicy.shouldRetainFinishedResults(
            queuePresented: isExportQueuePresented,
            hasFailures: exportBatchUnsuccessfulCount > 0
        ) {
            exportJobs.removeAll()
        }
    }

    private func restoreVideoSelectionAfterExport() {
        // 批量勾选仅用于导出；回到当前预览视频的单选状态以恢复编辑。
        exportVideoSelection = ExportVideoSelection().selectionAfterExport(
            from: project.videos,
            currentID: selectedVideoID
        )
    }

    private func availableOutputURL(
        for inputName: String,
        in directory: URL,
        excluding jobID: UUID? = nil,
        codec: ExportSettings.Codec? = nil
    ) -> URL {
        let baseName = URL(fileURLWithPath: inputName)
            .deletingPathExtension()
            .lastPathComponent
        let suffix = (codec ?? project.exportSettings.codec).fileExtension
        var index = 0

        while true {
            let name = index == 0
                ? "\(baseName)_RunOverlay.\(suffix)"
                : "\(baseName)_RunOverlay_\(index + 1).\(suffix)"
            let candidate = directory.appendingPathComponent(name)
            let reserved = exportJobs.contains {
                $0.id != jobID && $0.outputURL == candidate
            }
            if !reserved && !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func releaseActiveVideoAccess() {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeSecurityScopedURL = nil
    }

    private func releaseActiveTimeResourceAccess() {
        activeTimeResourceAccessURL?.stopAccessingSecurityScopedResource()
        activeTimeResourceAccessURL = nil
    }

    private func releaseActiveProjectFileAccess() {
        activeProjectFileAccessURL?.stopAccessingSecurityScopedResource()
        activeProjectFileAccessURL = nil
    }
}

struct PresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
