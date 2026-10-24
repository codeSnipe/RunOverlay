import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import RunOverlayCore
import XCTest

private struct ExportedVideoAudioSummary {
    var duration: TimeInterval
    var videoTrackCount: Int
    var audioTrackCount: Int
    var audioTrackRanges: [CMTimeRange]
}

@MainActor
final class SmartEditVideoExporterTests: XCTestCase {
    func test智能剪辑导出将主工作台选定路线图层烧录进MP4() async throws {
        guard ProcessInfo.processInfo.environment["RUNOVERLAY_SMART_EDIT_EXPORT"] == "1"
        else { throw XCTSkip("仅在明确开启本机真实素材验收时执行") }
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let demo = projectDirectory.appendingPathComponent("demo", isDirectory: true)
        let videoURL = demo.appendingPathComponent("DJI_20261002111755_0086_D.MP4")
        let fitURL = demo.appendingPathComponent("480745612738855213.fit")
        let lrfURL = demo.appendingPathComponent("DJI_20261002111755_0086_D.LRF")
        guard FileManager.default.isReadableFile(atPath: videoURL.path),
              FileManager.default.isReadableFile(atPath: fitURL.path) else {
            throw XCTSkip("当前工作区没有大疆演示视频或 FIT 运动数据")
        }

        let metadata = try await VideoMetadataReader().read(from: videoURL)
        let activity = try ActivityParser().parse(from: fitURL)
        let capturedAt = VideoTimeResourceReader().capturedAt(from: lrfURL)
            ?? metadata.capturedAt
        let match = VideoActivityMatcher().match(
            videoStart: capturedAt,
            duration: metadata.durationSeconds,
            activityRange: activity.timeRange
        )
        let start = try XCTUnwrap(capturedAt)
        XCTAssertEqual(match.status, .complete)

        var selectedLayer = OverlayConfiguration.preset(.runningFocus)
        let routeLayer = try XCTUnwrap(
            selectedLayer.elements.first(where: { $0.kind == .route })
        )
        selectedLayer.elements = [routeLayer]
        let source = SmartEditMediaSource(
            fileName: videoURL.lastPathComponent,
            fileURL: videoURL,
            motionStartSnapshot: start,
            motionOffsetSnapshot: match.timeOffset,
            overlayConfigurationSnapshot: selectedLayer,
            durationSeconds: metadata.durationSeconds,
            dimensions: metadata.dimensions,
            capturedAt: start,
            hasAudio: metadata.hasAudio
        )
        let duration = 3.2
        let activitySamples = ActivityTimeline().smoothed(
            samples: activity.samples,
            level: .standard
        )
        XCTAssertNotNil(ActivityTimeline().sample(
            at: start.addingTimeInterval(match.timeOffset + 1.5),
            in: activitySamples
        ))
        var draft = SmartEditDraft(
            name: "智能剪辑选定图层验收",
            sources: [source],
            clips: [
                SmartEditClip(
                    videoSourceID: source.id,
                    videoStartSeconds: 2,
                    videoEndSeconds: 2 + duration,
                    timelineStartSeconds: 0
                )
            ],
            audioSegments: metadata.hasAudio ? [
                SmartEditAudioSegment(
                    sourceID: source.id,
                    sourceStartSeconds: 2,
                    sourceEndSeconds: 2 + duration,
                    timelineStartSeconds: 0
                )
            ] : [],
            aspectRatio: .landscape16x9,
            maximumHeight: 480,
            activitySamples: activitySamples,
            activityTimeOffset: 0,
            activityStartSnapshot: activity.timeRange.start,
            videoTextLanguage: .chinese,
            overlayConfiguration: .preset(.minimal)
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunOverlay-SmartEdit-Layer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let plainURL = directory.appendingPathComponent("无图层.mp4")
        let layeredURL = directory.appendingPathComponent("主工作台路线图层.mp4")

        var hiddenLayer = selectedLayer
        for index in hiddenLayer.elements.indices {
            hiddenLayer.elements[index].isVisible = false
        }
        draft.sources[0].overlayConfigurationSnapshot = hiddenLayer
        try await SmartEditVideoExporter().export(draft, to: plainURL) { _ in }

        draft.sources[0].overlayConfigurationSnapshot = selectedLayer
        try await SmartEditVideoExporter().export(draft, to: layeredURL) { _ in }

        let plain = try Self.frame(in: AVURLAsset(url: plainURL), at: 1.5)
        let layered = try Self.frame(in: AVURLAsset(url: layeredURL), at: 1.5)
        XCTAssertGreaterThan(
            try Self.distinctPixels(layered, plain, inside: routeLayer.frame),
            60,
            "智能剪辑最终帧应烧录当前选择的路线图层"
        )
    }

    func test智能剪辑最终MP4烧录每段所选数据图层() async throws {
        guard ProcessInfo.processInfo.environment["RUNOVERLAY_SMART_EDIT_EXPORT"] == "1"
        else { throw XCTSkip("仅在明确开启本机真实素材验收时执行") }
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let demo = projectDirectory.appendingPathComponent("demo", isDirectory: true)
        let inputURL = demo.appendingPathComponent("DJI_20261002111755_0086_D.MP4")
        let fitURL = demo.appendingPathComponent("480745612738855213.fit")
        guard FileManager.default.isReadableFile(atPath: inputURL.path),
              FileManager.default.isReadableFile(atPath: fitURL.path) else {
            throw XCTSkip("当前工作区没有大疆演示视频或 FIT 运动数据")
        }

        let metadata = try await VideoMetadataReader().read(from: inputURL)
        let activity = try ActivityParser().parse(from: fitURL)
        let capturedAt = try XCTUnwrap(metadata.capturedAt)
        let matched = VideoActivityMatcher().match(
            videoStart: capturedAt,
            duration: metadata.durationSeconds,
            activityRange: activity.timeRange
        )
        XCTAssertEqual(matched.status, .complete)

        var selectedOverlay = OverlayConfiguration.preset(.runningFocus)
        selectedOverlay.elements = [try XCTUnwrap(
            selectedOverlay.elements.first(where: { $0.kind == .distance })
        )]
        let source = SmartEditMediaSource(
            fileName: inputURL.lastPathComponent,
            fileURL: inputURL,
            motionStartSnapshot: capturedAt,
            motionOffsetSnapshot: matched.timeOffset,
            overlayConfigurationSnapshot: selectedOverlay,
            durationSeconds: metadata.durationSeconds,
            dimensions: metadata.dimensions,
            capturedAt: capturedAt,
            hasAudio: metadata.hasAudio
        )
        var draft = SmartEditDraft(
            name: "主工作台图层验收",
            sources: [source],
            clips: [
                SmartEditClip(
                    videoSourceID: source.id,
                    videoStartSeconds: 2,
                    videoEndSeconds: 5.2,
                    timelineStartSeconds: 0
                )
            ],
            audioSegments: metadata.hasAudio ? [
                SmartEditAudioSegment(
                    sourceID: source.id,
                    sourceStartSeconds: 2,
                    sourceEndSeconds: 5.2,
                    timelineStartSeconds: 0
                )
            ] : [],
            aspectRatio: .landscape16x9,
            maximumHeight: 480,
            activitySamples: activity.samples,
            activityStartSnapshot: activity.timeRange.start,
            overlayConfiguration: .preset(.minimal)
        )
        var hiddenOverlay = selectedOverlay
        for index in hiddenOverlay.elements.indices {
            hiddenOverlay.elements[index].isVisible = false
        }
        draft.sources[0].overlayConfigurationSnapshot = hiddenOverlay

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunOverlay-SmartEdit-Layer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let plainURL = outputDirectory.appendingPathComponent("无图层.mp4")
        let overlayURL = outputDirectory.appendingPathComponent("带图层.mp4")
        try await SmartEditVideoExporter().export(draft, to: plainURL) { _ in }

        draft.sources[0].overlayConfigurationSnapshot = selectedOverlay
        draft.overlayConfiguration = .preset(.minimal)
        try await SmartEditVideoExporter().export(draft, to: overlayURL) { _ in }

        let plainAsset = AVURLAsset(url: plainURL)
        let overlayAsset = AVURLAsset(url: overlayURL)
        let plain = try Self.frame(in: plainAsset, at: 1.5)
        let overlay = try Self.frame(in: overlayAsset, at: 1.5)
        let outputDuration = try await overlayAsset.load(.duration).seconds
        XCTAssertEqual(outputDuration, 3.2, accuracy: 0.2)
        XCTAssertGreaterThan(
            try Self.distinctPixels(overlay, plain),
            80,
            "最终剪辑画面必须烧录所选的主工作台数据图层"
        )
    }

    private nonisolated static func frame(in asset: AVAsset, at seconds: Double) throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try generator.copyCGImage(
            at: CMTime(seconds: seconds, preferredTimescale: 600),
            actualTime: nil
        )
    }

    private nonisolated static func distinctPixels(
        _ lhs: CGImage,
        _ rhs: CGImage,
        inside normalized: NormalizedRect? = nil
    ) throws -> Int {
        XCTAssertEqual(lhs.width, rhs.width)
        XCTAssertEqual(lhs.height, rhs.height)
        let width = lhs.width
        let height = lhs.height
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        func bytes(_ image: CGImage) -> [UInt8] {
            var result = [UInt8](repeating: 0, count: width * height * 4)
            result.withUnsafeMutableBytes { buffer in
                guard let address = buffer.baseAddress else { return }
                context.render(
                    CIImage(cgImage: image),
                    toBitmap: address,
                    rowBytes: width * 4,
                    bounds: CGRect(x: 0, y: 0, width: width, height: height),
                    format: .RGBA8,
                    colorSpace: colorSpace
                )
            }
            return result
        }
        let first = bytes(lhs)
        let second = bytes(rhs)
        let xRange: Range<Int>
        let yRange: Range<Int>
        if let normalized {
            let minX = max(0, Int(normalized.x * Double(width)))
            let maxX = min(width, Int((normalized.x + normalized.width) * Double(width)))
            let minY = max(0, Int(normalized.y * Double(height)))
            let maxY = min(height, Int((normalized.y + normalized.height) * Double(height)))
            xRange = minX..<maxX
            yRange = minY..<maxY
        } else {
            xRange = 0..<width
            yRange = 0..<height
        }
        var count = 0
        for y in yRange {
            for x in xRange {
                let index = (y * width + x) * 4
                let difference = (0..<3).reduce(0) {
                    $0 + abs(Int(first[index + $1]) - Int(second[index + $1]))
                }
                if difference > 75 { count += 1 }
            }
        }
        return count
    }

    func test演示视频自动分析与实际裁剪方案() async throws {
        guard ProcessInfo.processInfo.environment["RUNOVERLAY_SMART_EDIT_EXPORT"] == "1"
        else { throw XCTSkip("仅在明确开启本机真实素材验收时执行") }
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let files = [
            "demo/DJI_20261002111755_0086_D.MP4",
            "demo/DJI_20261002111832_0087_D.MP4"
        ]
        var sources: [SmartEditMediaSource] = []
        // 测试进程没有语音隐私权限；仅测画面与音频波形本机分析。
        let analyzer = LocalSmartEditAnalyzer(
            locale: Locale(identifier: "zh-CN"),
            recognizesSpeech: false
        )
        for file in files {
            let url = projectDirectory.appendingPathComponent(file)
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw XCTSkip("当前工作区没有大疆演示视频")
            }
            let analysis = try await analyzer.analyze(
                fileURL: url,
                analyzesSpeech: false
            )
            sources.append(analysis.source)
        }
        let summary = SmartEditAnalysisSummary(sources: sources)
        let draft = SmartEditDraftBuilder().makeAutomaticDraft(
            name: "本机自动裁剪验收",
            sources: sources,
            maximumHeight: 480
        )
        XCTAssertEqual(summary.outputDurationSeconds, draft.durationSeconds, accuracy: 0.001)
        XCTAssertLessThan(summary.outputDurationSeconds, summary.totalDurationSeconds)
        XCTAssertNoThrow(try SmartEditDraftCodec().encode(draft))
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunOverlay-AutoEdit-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try await SmartEditVideoExporter().export(draft, to: outputURL) { _ in }
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(duration, draft.durationSeconds, accuracy: 0.2)
        XCTAssertEqual(video.count, 1)
        XCTAssertEqual(audio.count, 1)
        if let outputPath = ProcessInfo.processInfo.environment["RUNOVERLAY_SMART_EDIT_OUTPUT"] {
            let savedURL = URL(fileURLWithPath: outputPath)
            guard !FileManager.default.fileExists(atPath: savedURL.path) else {
                throw SmartEditVideoExporterError.outputAlreadyExists
            }
            try FileManager.default.copyItem(at: outputURL, to: savedURL)
        }
    }

    func test旧版HEVC草稿仍导出MP4文件() throws {
        let draft = SmartEditDraft(
            name: "老草稿",
            clips: [
                SmartEditClip(
                    videoSourceID: UUID(),
                    videoStartSeconds: 1,
                    videoEndSeconds: 2
                )
            ],
            codec: .hevc
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunOverlay-SmartEdit-Jobs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let job = try SmartEditVideoExporter().makeJob(
            from: draft,
            exportDirectory: directory
        )

        XCTAssertEqual(job.outputURL.pathExtension, "mp4")
    }

    func test直接导出时同名MP4自动编号且不会覆盖已有文件() throws {
        let draft = SmartEditDraft(
            name: "跑步 Vlog",
            clips: [
                SmartEditClip(
                    videoSourceID: UUID(),
                    videoStartSeconds: 0,
                    videoEndSeconds: 2
                )
            ]
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunOverlay-SmartEdit-Naming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("跑步 Vlog.mp4")
        let numbered = directory.appendingPathComponent("跑步 Vlog-2.mp4")
        try Data([1]).write(to: existing)
        try Data([2]).write(to: numbered)

        let job = try SmartEditVideoExporter().makeJob(from: draft, exportDirectory: directory)

        XCTAssertEqual(job.outputURL.lastPathComponent, "跑步 Vlog-3.mp4")
        XCTAssertEqual(try Data(contentsOf: existing), Data([1]))
        XCTAssertEqual(try Data(contentsOf: numbered), Data([2]))
    }

    func test已保存的完整剪辑草稿导出裁剪后的MP4() async throws {
        guard let draftPath = ProcessInfo.processInfo.environment["RUNOVERLAY_SMART_EDIT_DRAFT"] else {
            throw XCTSkip("仅在提供已保存草稿时执行真实成片导出验收")
        }
        var draft = try SmartEditDraftCodec().load(
            from: URL(fileURLWithPath: draftPath)
        )
        let environment = ProcessInfo.processInfo.environment
        if let count = environment["RUNOVERLAY_SMART_EDIT_CLIP_COUNT"].flatMap(Int.init) {
            draft.clips = Array(draft.clips.prefix(count))
            let maximumDuration = draft.clips.last?.timelineEndSeconds ?? 0
            draft.audioSegments = draft.audioSegments.compactMap { segment in
                guard segment.timelineStartSeconds < maximumDuration else { return nil }
                var segment = segment
                segment.sourceEndSeconds = min(
                    segment.sourceEndSeconds,
                    segment.sourceStartSeconds + maximumDuration - segment.timelineStartSeconds
                )
                return segment
            }
        }
        if let height = environment["RUNOVERLAY_SMART_EDIT_HEIGHT"].flatMap(Int.init) {
            draft.maximumHeight = height
        }
        if environment["RUNOVERLAY_SMART_EDIT_TRIM_PREFIX"] == "1",
           let firstClip = draft.clips.first {
            let originalDuration = firstClip.durationSeconds
            let newStart = min(firstClip.videoStartSeconds + 0.7, firstClip.videoEndSeconds - 0.2)
            draft.clips[0].videoStartSeconds = newStart
            let difference = originalDuration - draft.clips[0].durationSeconds
            for index in draft.clips.indices where index > 0 {
                draft.clips[index].timelineStartSeconds -= difference
            }
            if !draft.audioSegments.isEmpty {
                draft.audioSegments[0].sourceStartSeconds += difference
                for index in draft.audioSegments.indices where index > 0 {
                    draft.audioSegments[index].timelineStartSeconds -= difference
                }
            }
        }
        if let end = environment["RUNOVERLAY_SMART_EDIT_TRIM_VIDEO_END"].flatMap(Double.init),
           let index = draft.clips.indices.last {
            draft.clips[index].videoEndSeconds = end
            let maximumDuration = draft.clips[index].timelineEndSeconds
            draft.audioSegments = draft.audioSegments.compactMap { segment in
                guard segment.timelineStartSeconds < maximumDuration else { return nil }
                var segment = segment
                segment.sourceEndSeconds = min(
                    segment.sourceEndSeconds,
                    segment.sourceStartSeconds + maximumDuration - segment.timelineStartSeconds
                )
                return segment
            }
        }
        let outputURL: URL
        if let outputPath = environment["RUNOVERLAY_SMART_EDIT_OUTPUT"] {
            outputURL = URL(fileURLWithPath: outputPath)
            XCTAssertEqual(outputURL.pathExtension.lowercased(), "mp4")
        } else {
            outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("RunOverlay-SmartEdit-Full-\(UUID().uuidString)")
                .appendingPathComponent("已剪辑验收.mp4")
        }
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try await SmartEditVideoExporter().export(draft, to: outputURL) { _ in }
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(duration, draft.durationSeconds, accuracy: 0.2)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, draft.audioSegments.isEmpty ? 0 : 1)
        if draft.sources.count > 1,
           draft.clips.count > 9 {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 64, height: 64)
            let firstFrame = try generator.copyCGImage(
                at: CMTime(seconds: 2, preferredTimescale: 600),
                actualTime: nil
            )
            let secondTime = draft.clips[9].timelineStartSeconds + 1
            let secondFrame = try generator.copyCGImage(
                at: CMTime(seconds: secondTime, preferredTimescale: 600),
                actualTime: nil
            )
            let firstData = try XCTUnwrap(firstFrame.dataProvider?.data) as Data
            let secondData = try XCTUnwrap(secondFrame.dataProvider?.data) as Data
            XCTAssertNotEqual(firstData, secondData, "成片在第二个素材位置应显示不同画面")
        }
    }

    func test修改入出点并更换画面顺序后导出MP4() async throws {
        guard ProcessInfo.processInfo.environment["RUNOVERLAY_SMART_EDIT_EXPORT"] == "1" else {
            throw XCTSkip("仅在明确开启本机智能成片真实素材验收时执行")
        }
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let inputURL = projectDirectory.appendingPathComponent(
            "demo/DJI_20261002111755_0086_D.MP4"
        )
        guard FileManager.default.isReadableFile(atPath: inputURL.path) else {
            throw XCTSkip("当前工作区没有大疆演示视频")
        }

        let metadata = try await VideoMetadataReader().read(from: inputURL)
        let source = SmartEditMediaSource(
            fileName: inputURL.lastPathComponent,
            fileURL: inputURL,
            durationSeconds: metadata.durationSeconds,
            dimensions: metadata.dimensions,
            hasAudio: metadata.hasAudio
        )
        let draft = SmartEditDraft(
            name: "剪辑出入点验收",
            sources: [source],
            clips: [
                SmartEditClip(
                    videoSourceID: source.id,
                    videoStartSeconds: 6,
                    videoEndSeconds: 7.75,
                    timelineStartSeconds: 0
                ),
                SmartEditClip(
                    videoSourceID: source.id,
                    videoStartSeconds: 2,
                    videoEndSeconds: 4.25,
                    timelineStartSeconds: 1.75
                )
            ],
            audioSegments: metadata.hasAudio ? [
                SmartEditAudioSegment(
                    sourceID: source.id,
                    sourceStartSeconds: 0,
                    sourceEndSeconds: 4,
                    timelineStartSeconds: 0
                )
            ] : [],
            aspectRatio: .landscape16x9,
            maximumHeight: 480
        )
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunOverlay-SmartEdit-Trim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let outputURL = outputDirectory.appendingPathComponent("剪辑结果.mp4")

        try await SmartEditVideoExporter().export(draft, to: outputURL) { _ in }

        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(duration, 4, accuracy: 0.16)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, metadata.hasAudio ? 1 : 0)
    }

    func testDJI短片画面剪切后原声独立连续合成() async throws {
        guard ProcessInfo.processInfo.environment["RUNOVERLAY_SMART_EDIT_EXPORT"] == "1" else {
            throw XCTSkip("仅在明确开启本机智能成片真实素材验收时执行")
        }
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let inputURL = projectDirectory.appendingPathComponent(
            "demo/DJI_20261002111755_0086_D.MP4"
        )
        guard FileManager.default.isReadableFile(atPath: inputURL.path) else {
            throw XCTSkip("当前工作区没有大疆演示视频")
        }

        let metadata = try await VideoMetadataReader().read(from: inputURL)
        let source = SmartEditMediaSource(
            fileName: inputURL.lastPathComponent,
            fileURL: inputURL,
            durationSeconds: metadata.durationSeconds,
            dimensions: metadata.dimensions,
            capturedAt: metadata.capturedAt,
            hasAudio: metadata.hasAudio
        )
        let shortDuration: TimeInterval = 3.2
        let draft = SmartEditDraft(
            name: "本机智能成片真实素材验收",
            sources: [source],
            clips: [
                SmartEditClip(
                    videoSourceID: source.id,
                    videoStartSeconds: 2,
                    videoEndSeconds: 2 + shortDuration,
                    timelineStartSeconds: 0
                )
            ],
            audioSegments: metadata.hasAudio
                ? [
                    SmartEditAudioSegment(
                        sourceID: source.id,
                        sourceStartSeconds: 0,
                        sourceEndSeconds: shortDuration,
                        timelineStartSeconds: 0
                    )
                ]
                : [],
            aspectRatio: .landscape16x9,
            maximumHeight: 480
        )
        let outputDirectory = projectDirectory.appendingPathComponent(
            ".build/SmartEditExportSmoke-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let outputURL = outputDirectory.appendingPathComponent("剪辑验收.mp4")

        try await SmartEditVideoExporter().export(draft, to: outputURL) { _ in }

        let exported = AVURLAsset(url: outputURL)
        let duration = try await exported.load(.duration).seconds
        XCTAssertEqual(duration, shortDuration, accuracy: 0.16)
        let videoTracks = try await exported.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)
        if metadata.hasAudio {
            let audioTracks = try await exported.loadTracks(withMediaType: .audio)
            XCTAssertEqual(audioTracks.count, 1)
        }
    }

    func test跨来源重排画面时保留原始口播时间线() async throws {
        guard ProcessInfo.processInfo.environment["RUNOVERLAY_SMART_EDIT_EXPORT"] == "1" else {
            throw XCTSkip("仅在明确开启本机智能成片真实素材验收时执行")
        }
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let firstURL = projectDirectory.appendingPathComponent(
            "demo/DJI_20261002111755_0086_D.MP4"
        )
        let secondURL = projectDirectory.appendingPathComponent(
            "demo/DJI_20261002111832_0087_D.MP4"
        )
        guard FileManager.default.isReadableFile(atPath: firstURL.path),
              FileManager.default.isReadableFile(atPath: secondURL.path) else {
            throw XCTSkip("当前工作区没有两段大疆演示视频")
        }
        async let firstMetadata = VideoMetadataReader().read(from: firstURL)
        async let secondMetadata = VideoMetadataReader().read(from: secondURL)
        let metadata = try await [firstMetadata, secondMetadata]
        let first = SmartEditMediaSource(
            fileName: firstURL.lastPathComponent,
            fileURL: firstURL,
            originalVideoID: UUID(),
            motionStartSnapshot: Date(timeIntervalSince1970: 1_800_000_000),
            motionOffsetSnapshot: 0.25,
            durationSeconds: metadata[0].durationSeconds,
            dimensions: metadata[0].dimensions,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            hasAudio: metadata[0].hasAudio,
            sceneBoundaries: [4]
        )
        let second = SmartEditMediaSource(
            fileName: secondURL.lastPathComponent,
            fileURL: secondURL,
            originalVideoID: UUID(),
            motionStartSnapshot: Date(timeIntervalSince1970: 1_800_000_400),
            motionOffsetSnapshot: -0.15,
            durationSeconds: metadata[1].durationSeconds,
            dimensions: metadata[1].dimensions,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_400),
            hasAudio: metadata[1].hasAudio
        )
        let duration = 4.0
        let draft = SmartEditDraft(
            name: "跨来源音轨验收",
            sources: [first, second],
            clips: [
                SmartEditClip(
                    videoSourceID: second.id,
                    videoStartSeconds: 0,
                    videoEndSeconds: duration,
                    timelineStartSeconds: 0
                ),
                SmartEditClip(
                    videoSourceID: first.id,
                    videoStartSeconds: 0,
                    videoEndSeconds: duration,
                    timelineStartSeconds: duration
                )
            ],
            audioSegments: [
                SmartEditAudioSegment(
                    sourceID: first.id,
                    sourceStartSeconds: 0,
                    sourceEndSeconds: duration,
                    timelineStartSeconds: 0
                ),
                SmartEditAudioSegment(
                    sourceID: second.id,
                    sourceStartSeconds: 0,
                    sourceEndSeconds: duration,
                    timelineStartSeconds: duration
                )
            ],
            aspectRatio: .landscape16x9,
            maximumHeight: 480,
            activitySamples: Self.makeActivitySamples(start: 1_800_000_000),
            activityTimeOffset: 0.35,
            overlayConfiguration: .preset(.stadiumLive)
        )
        let outputDirectory = projectDirectory.appendingPathComponent(
            ".build/SmartEditCrossSource-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let outputURL = outputDirectory.appendingPathComponent("跨来源重排.mp4")

        try await SmartEditVideoExporter().export(draft, to: outputURL) { _ in }

        let summary = try await Self.audioSummary(of: outputURL)
        XCTAssertEqual(summary.videoTrackCount, 1)
        XCTAssertGreaterThanOrEqual(summary.audioTrackCount, 1)
        XCTAssertTrue(summary.audioTrackRanges.contains {
            abs($0.start.seconds) < 0.05 &&
                abs($0.duration.seconds - duration * 2) < 0.2
        })
        XCTAssertEqual(summary.duration, duration * 2, accuracy: 0.2)
    }

    func test视频原声跨无声片段后继续且无需额外录音() async throws {
        guard ProcessInfo.processInfo.environment["RUNOVERLAY_SMART_EDIT_EXPORT"] == "1" else {
            throw XCTSkip("仅在明确开启本机智能成片真实素材验收时执行")
        }
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let videoURL = projectDirectory.appendingPathComponent(
            "demo/DJI_20261002111755_0086_D.MP4"
        )
        guard FileManager.default.isReadableFile(atPath: videoURL.path) else {
            throw XCTSkip("当前工作区没有大疆演示视频")
        }
        let metadata = try await VideoMetadataReader().read(from: videoURL)
        guard metadata.hasAudio, metadata.durationSeconds > 6 else {
            throw XCTSkip("演示视频没有足够长的视频自带音轨")
        }
        let audio = SmartEditMediaSource(
            fileName: videoURL.lastPathComponent,
            fileURL: videoURL,
            durationSeconds: metadata.durationSeconds,
            dimensions: metadata.dimensions,
            hasAudio: true
        )
        // 测试无音轨素材的时间线行为；画面复用短片，音轨由 hasAudio 排除。
        let silent = SmartEditMediaSource(
            fileName: "无声画面.mp4",
            fileURL: videoURL,
            durationSeconds: metadata.durationSeconds,
            dimensions: metadata.dimensions,
            hasAudio: false
        )
        let firstDuration = 2.0
        let silentDuration = 1.5
        let lastDuration = 2.0
        let draft = SmartEditDraft(
            name: "视频原声与无声片段",
            sources: [audio, silent],
            clips: [
                SmartEditClip(
                    videoSourceID: audio.id,
                    videoStartSeconds: 0,
                    videoEndSeconds: firstDuration,
                    timelineStartSeconds: 0
                ),
                SmartEditClip(
                    videoSourceID: silent.id,
                    videoStartSeconds: 0,
                    videoEndSeconds: silentDuration,
                    timelineStartSeconds: firstDuration
                ),
                SmartEditClip(
                    videoSourceID: audio.id,
                    videoStartSeconds: 2.5,
                    videoEndSeconds: 2.5 + lastDuration,
                    timelineStartSeconds: firstDuration + silentDuration
                )
            ],
            audioSegments: [
                SmartEditAudioSegment(
                    sourceID: audio.id,
                    sourceStartSeconds: 0,
                    sourceEndSeconds: firstDuration,
                    timelineStartSeconds: 0
                ),
                SmartEditAudioSegment(
                    sourceID: audio.id,
                    sourceStartSeconds: firstDuration,
                    sourceEndSeconds: firstDuration + lastDuration,
                    timelineStartSeconds: firstDuration + silentDuration
                )
            ],
            aspectRatio: .landscape16x9,
            maximumHeight: 480
        )
        let outputDirectory = projectDirectory.appendingPathComponent(
            ".build/SmartEditSourceAudio-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let outputURL = outputDirectory.appendingPathComponent("原声与静音.mp4")

        try await SmartEditVideoExporter().export(draft, to: outputURL) { _ in }

        let summary = try await Self.audioSummary(of: outputURL)
        XCTAssertEqual(summary.videoTrackCount, 1)
        XCTAssertEqual(summary.audioTrackCount, 1)
        XCTAssertEqual(summary.duration, firstDuration + silentDuration + lastDuration, accuracy: 0.2)
    }

    private nonisolated static func audioSummary(
        of url: URL
    ) async throws -> ExportedVideoAudioSummary {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioTrackRanges: [CMTimeRange] = []
        for track in audioTracks {
            audioTrackRanges.append(try await track.load(.timeRange))
        }
        return ExportedVideoAudioSummary(
            duration: duration,
            videoTrackCount: videoTracks.count,
            audioTrackCount: audioTracks.count,
            audioTrackRanges: audioTrackRanges
        )
    }

    private nonisolated static func makeActivitySamples(start: TimeInterval) -> [ActivitySample] {
        var result: [ActivitySample] = []
        for index in 0..<40 {
            let offset = Double(index)
            let point = GeoCoordinate(
                latitude: 31.0 + offset * 0.00001,
                longitude: 121.0 + offset * 0.00001
            )
            result.append(ActivitySample(
                timestamp: Date(timeIntervalSince1970: start + offset),
                coordinate: point,
                distanceMeters: offset * 2,
                speedMetersPerSecond: 3.2,
                heartRate: 140,
                altitudeMeters: 8 + offset * 0.1,
                ascentMeters: offset * 0.1,
                caloriesKilocalories: offset * 0.5
            ))
        }
        return result
    }

}
