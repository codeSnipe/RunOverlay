import Foundation
import XCTest
@testable import RunOverlayCore

final class VideoTimeResourceReaderTests: XCTestCase {
    func test诊断时间来源偏差和手动修正可保存并重新匹配() throws {
        let activityStart = Date(timeIntervalSince1970: 1_000)
        let activityRange = DateInterval(start: activityStart, duration: 120)
        var video = VideoItem(
            fileName: "DJI_20261002111755_0086_D.MP4",
            fileURL: URL(fileURLWithPath: "/camera/DJI_20261002111755_0086_D.MP4"),
            metadata: VideoAssetMetadata(
                durationSeconds: 30,
                dimensions: PixelDimensions(width: 1920, height: 1080),
                frameRate: 30,
                capturedAt: activityStart.addingTimeInterval(150),
                captureTimeSource: .container,
                hasAudio: true,
                container: "MP4",
                fileSizeBytes: 100
            )
        )
        let matcher = VideoActivityMatcher()
        video.activityMatch = matcher.match(
            videoStart: video.effectiveCapturedAt,
            duration: video.metadata.durationSeconds,
            activityRange: activityRange
        )
        XCTAssertEqual(video.activityMatch.status, .unmatched)
        let initial = VideoMatchDiagnostic(video: video, activityRange: activityRange)
        XCTAssertEqual(initial.captureSource, .container)
        XCTAssertEqual(initial.secondsFromActivityStart, 150)
        XCTAssertEqual(initial.secondsAfterActivity, 30)

        video.manualCapturedAt = activityStart.addingTimeInterval(105)
        video.activityMatch = matcher.match(
            videoStart: video.effectiveCapturedAt,
            duration: video.metadata.durationSeconds,
            activityRange: activityRange
        )
        XCTAssertEqual(video.activityMatch.status, .partial)
        let corrected = VideoMatchDiagnostic(video: video, activityRange: activityRange)
        XCTAssertEqual(corrected.captureSource, .manual)
        XCTAssertEqual(corrected.secondsAfterActivity, 15)
        let restored = try JSONDecoder().decode(
            VideoItem.self,
            from: JSONEncoder().encode(video)
        )
        XCTAssertEqual(restored.manualCapturedAt, video.manualCapturedAt)
        XCTAssertEqual(restored.effectiveCaptureTimeSource, .manual)
        XCTAssertEqual(restored.activityMatch.status, .partial)

        video.manualCapturedAt = nil
        XCTAssertEqual(video.effectiveCaptureTimeSource, .container)
        XCTAssertEqual(video.effectiveCapturedAt, video.metadata.capturedAt)
    }

    func test手动时间格式严格校验并兼容旧项目() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3_600))
        let text = "2026-10-02 11:17:55"
        let date = try XCTUnwrap(VideoCaptureTimeFormatter.parse(text, timeZone: zone))
        XCTAssertEqual(VideoCaptureTimeFormatter.format(date, timeZone: zone), text)
        XCTAssertNil(VideoCaptureTimeFormatter.parse("2026-02-30 11:17:55", timeZone: zone))
        XCTAssertNil(VideoCaptureTimeFormatter.parse("2026-10-02 25:17:55", timeZone: zone))

        let oldJSON = """
        {"id":"00000000-0000-0000-0000-000000000001",
         "fileName":"old.mp4","fileURL":"/old.mp4",
         "metadata":{"durationSeconds":10,"dimensions":{"width":1920,"height":1080},
         "frameRate":30,"capturedAt":0,"hasAudio":true,"container":"MP4",
         "fileSizeBytes":100},
         "activityMatch":{"status":"pending","timeOffset":0,"calibrationMethod":"automatic"},
         "rotation":0}
        """
        let previous = try JSONDecoder().decode(VideoItem.self, from: Data(oldJSON.utf8))
        XCTAssertNil(previous.manualCapturedAt)
        XCTAssertEqual(previous.effectiveCaptureTimeSource, .unavailable)
    }

    func test没有拍摄时间和运动文件时诊断不会伪造偏差() {
        let video = VideoItem(
            fileName: "unknown.mp4",
            fileURL: URL(fileURLWithPath: "/camera/unknown.mp4"),
            metadata: VideoAssetMetadata(
                durationSeconds: 10,
                dimensions: PixelDimensions(width: 1920, height: 1080),
                frameRate: 30,
                capturedAt: nil,
                hasAudio: false,
                container: "MP4",
                fileSizeBytes: 100
            )
        )
        let diagnostic = VideoMatchDiagnostic(video: video, activityRange: nil)
        XCTAssertEqual(diagnostic.captureSource, .unavailable)
        XCTAssertNil(diagnostic.secondsFromActivityStart)
        XCTAssertNil(diagnostic.alignedStart)
    }

    func test时间资源回退和校准偏移反映到匹配诊断() {
        let activityStart = Date(timeIntervalSince1970: 1_000)
        let video = VideoItem(
            fileName: "custom.mp4",
            fileURL: URL(fileURLWithPath: "/camera/custom.mp4"),
            metadata: VideoAssetMetadata(
                durationSeconds: 30,
                dimensions: PixelDimensions(width: 1920, height: 1080),
                frameRate: 30,
                capturedAt: nil,
                hasAudio: true,
                container: "MP4",
                fileSizeBytes: 100
            ),
            activityMatch: ActivityMatch(timeOffset: 5),
            timeResource: VideoTimeResource(
                fileName: "custom.lrv",
                fileURL: URL(fileURLWithPath: "/camera/custom.lrv"),
                capturedAt: activityStart.addingTimeInterval(10)
            )
        )
        let diagnostic = VideoMatchDiagnostic(
            video: video,
            activityRange: DateInterval(start: activityStart, duration: 20)
        )
        XCTAssertEqual(diagnostic.captureSource, .timeResource)
        XCTAssertEqual(diagnostic.recordedStart, activityStart.addingTimeInterval(10))
        XCTAssertEqual(diagnostic.alignedStart, activityStart.addingTimeInterval(15))
        XCTAssertEqual(diagnostic.secondsFromActivityStart, 15)
        XCTAssertEqual(diagnostic.secondsAfterActivity, 25)
    }

    func test从LRV文件名解析毫秒级本地拍摄时间() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let expected = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 9,
                    day: 22,
                    hour: 6,
                    minute: 22,
                    second: 16,
                    nanosecond: 378_000_000
                )
            )
        )
        let url = URL(
            fileURLWithPath: "/camera/LRV_20260922_062216_378.lrv"
        )

        XCTAssertEqual(
            VideoTimeResourceReader().capturedAt(from: url),
            expected
        )
    }

    func test无法从随机名称推断时间() {
        let url = URL(fileURLWithPath: "/camera/random-name.lrv")

        XCTAssertNil(VideoTimeResourceReader().capturedAt(from: url))
    }

    func test大疆文件名解析本地拍摄时间并适用于视频和LRF() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 2,
            hour: 11, minute: 17, second: 55
        )))
        let reader = VideoTimeResourceReader()
        XCTAssertEqual(
            reader.capturedAt(from: URL(
                fileURLWithPath: "/camera/DJI_20261002111755_0086_D.MP4"
            )),
            expected
        )
        XCTAssertEqual(
            reader.capturedAt(from: URL(
                fileURLWithPath: "/camera/DJI_20261002111755_0086_D.LRF"
            )),
            expected
        )
        XCTAssertNil(reader.capturedAt(from: URL(
            fileURLWithPath: "/camera/DJI_20261302111755_0086_D.LRF"
        )))
        XCTAssertNil(reader.capturedAt(from: URL(
            fileURLWithPath: "/camera/DJI_20261002111755_INVALID_D.LRF"
        )))
    }

    func test手动导入按大疆和影石规则查找时间资源() {
        let reader = VideoTimeResourceReader()
        XCTAssertEqual(
            Set(reader.candidateFileNames(
                forVideoName: "DJI_20261002111755_0086_D.MP4"
            )),
            Set([
                "dji_20261002111755_0086_d.lrf",
                "dji_20261002111755_0086_d.lrv"
            ])
        )
        XCTAssertTrue(reader.candidateFileNames(
            forVideoName: "VID_20260922_062216_378.mp4"
        ).contains("lrv_20260922_062216_378.lrv"))
    }

    func test容器拍摄时间优先LRV回退时间() {
        let containerTime = Date(timeIntervalSince1970: 10)
        let sidecarTime = Date(timeIntervalSince1970: 20)
        let activityRange = DateInterval(
            start: containerTime,
            duration: 60
        )
        let matcher = VideoActivityMatcher()

        let withContainerTime = matcher.match(
            videoStart: containerTime,
            duration: 10,
            sidecarCaptureDate: sidecarTime,
            activityRange: activityRange
        )
        let sidecarFallback = matcher.match(
            videoStart: nil,
            duration: 10,
            sidecarCaptureDate: sidecarTime,
            activityRange: activityRange
        )

        XCTAssertEqual(withContainerTime.status, .complete)
        XCTAssertEqual(sidecarFallback.status, .complete)
        XCTAssertEqual(
            sidecarFallback.matchedRange?.start,
            sidecarTime
        )
    }

    func test两组同名视频分别采用各自LRV时间匹配活动() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let names = [
            "LRV_20260922_062216_378.mp4",
            "LRV_20260922_062457_379.mp4"
        ]
        var videos: [VideoItem] = []
        for name in names {
            let videoURL = root.appendingPathComponent(name)
            let sidecarURL = videoURL
                .deletingPathExtension()
                .appendingPathExtension("lrv")
            try Data().write(to: videoURL)
            try Data().write(to: sidecarURL)
            videos.append(
                VideoItem(
                    fileName: name,
                    fileURL: videoURL,
                    metadata: VideoAssetMetadata(
                        durationSeconds: 5,
                        dimensions: PixelDimensions(width: 960, height: 540),
                        frameRate: 30,
                        capturedAt: nil,
                        hasAudio: false,
                        container: "MP4",
                        fileSizeBytes: 0
                    ),
                    timeResource: VideoTimeResource(
                        fileName: sidecarURL.lastPathComponent,
                        fileURL: sidecarURL,
                        capturedAt: try XCTUnwrap(
                            VideoTimeResourceReader().capturedAt(from: sidecarURL)
                        )
                    )
                )
            )
        }

        let activityStart = try XCTUnwrap(videos.first?.effectiveCapturedAt)
        let activityEnd = try XCTUnwrap(videos.last?.effectiveCapturedAt)
            .addingTimeInterval(5)
        let matched = VideoActivityMatcher().match(
            videos: videos,
            activityRange: DateInterval(start: activityStart, end: activityEnd)
        )

        XCTAssertEqual(matched.map(\.activityMatch.status), [.complete, .complete])
    }

    func testDemo两段大疆视频及LRF与FIT实际匹配() async throws {
        let demo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("demo", isDirectory: true)
        let names = [
            "DJI_20261002111755_0086_D",
            "DJI_20261002111832_0087_D"
        ]
        let activityURL = demo.appendingPathComponent("480745612738855213.fit")
        guard FileManager.default.isReadableFile(atPath: activityURL.path),
              names.allSatisfy({
                  FileManager.default.isReadableFile(
                      atPath: demo.appendingPathComponent("\($0).MP4").path
                  ) && FileManager.default.isReadableFile(
                      atPath: demo.appendingPathComponent("\($0).LRF").path
                  )
              })
        else {
            throw XCTSkip("当前工作区没有完整的大疆 demo 素材")
        }

        // 只核验原始素材：demo/result 中可能已有用户导出的 MP4，不应计入输入视频。
        let inputs = names.flatMap { name in
            [
                demo.appendingPathComponent("\(name).MP4"),
                demo.appendingPathComponent("\(name).LRF")
            ]
        } + [activityURL]
        let batch = MediaDropScanner().scan(inputs)
        XCTAssertEqual(batch.videoURLs.count, 2)
        XCTAssertEqual(batch.timeResourcesByVideoURL.count, 2)
        XCTAssertTrue(batch.ambiguousVideoURLs.isEmpty)
        let activity = try ActivityParser().parse(from: activityURL)
        let reader = VideoMetadataReader()
        let timeReader = VideoTimeResourceReader()
        let matcher = VideoActivityMatcher()

        for name in names {
            let video = demo.appendingPathComponent("\(name).MP4")
            let sidecar = try XCTUnwrap(
                batch.timeResourcesByVideoURL[
                    video.resolvingSymlinksInPath().standardizedFileURL
                ]
            )
            XCTAssertEqual(sidecar.lastPathComponent, "\(name).LRF")
            let metadata = try await reader.read(from: video)
            let capturedAt = try XCTUnwrap(metadata.capturedAt)
            XCTAssertEqual(capturedAt, timeReader.capturedAt(from: sidecar))
            let match = matcher.match(
                videoStart: capturedAt,
                duration: metadata.durationSeconds,
                activityRange: activity.timeRange
            )
            XCTAssertEqual(match.status, .complete, name)
            XCTAssertNotNil(
                ActivityTimeline().sample(
                    at: capturedAt.addingTimeInterval(5),
                    in: activity.samples
                ),
                "\(name) 的视频时间应能读取到运动数据"
            )
        }
    }
}
