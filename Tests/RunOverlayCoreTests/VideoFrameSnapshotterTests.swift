@preconcurrency import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import RunOverlayCore

final class VideoFrameSnapshotterTests: XCTestCase {
    func test截图优先使用当前暂停帧而非滞后的界面时间() {
        XCTAssertEqual(
            VideoFrameSnapshotter.captureTime(
                playerTime: 5.133,
                fallbackTime: 5.0,
                duration: 20,
                frameRate: 30
            ),
            5.133,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            VideoFrameSnapshotter.captureTime(
                playerTime: .nan,
                fallbackTime: 5.0,
                duration: 20,
                frameRate: 30
            ),
            5.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            VideoFrameSnapshotter.captureTime(
                playerTime: 20,
                fallbackTime: 0,
                duration: 20,
                frameRate: 25
            ),
            19.96,
            accuracy: 0.000_001
        )
    }

    func test实际大疆视频截图包含运动数据且匹配导出画幅() throws {
        let demo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("demo", isDirectory: true)
        let input = demo.appendingPathComponent("DJI_20261002111755_0086_D.MP4")
        let activityFile = demo.appendingPathComponent("480745612738855213.fit")
        guard FileManager.default.isReadableFile(atPath: input.path),
              FileManager.default.isReadableFile(atPath: activityFile.path) else {
            throw XCTSkip("当前工作区没有完整的大疆演示素材")
        }

        let activity = try ActivityParser().parse(from: activityFile)
        let captureTime = try XCTUnwrap(VideoTimeResourceReader().capturedAt(from: input))
        let snapshotSecond = 5.0
        let currentSample = try XCTUnwrap(
            ActivityTimeline().sample(
                at: captureTime.addingTimeInterval(snapshotSecond),
                in: activity.samples
            )
        )
        XCTAssertNotNil(currentSample.coordinate)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let settings = ExportSettings(
            maximumHeight: 480,
            aspectRatio: .portrait9x16
        )
        let output = directory.appendingPathComponent("当前帧.png")
        let withOverlay = VideoExportRequest(
            inputURL: input,
            outputURL: output,
            videoStart: captureTime,
            timeOffset: 0,
            overlay: .preset(.runningFocus),
            activitySamples: activity.samples,
            activityStart: activity.timeRange.start,
            settings: settings,
            rotation: .clockwise90
        )
        try VideoFrameSnapshotter().capture(
            withOverlay,
            at: snapshotSecond,
            includeDataLayer: true
        )

        let saved = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(saved) as String?, UTType.png.identifier)
        let frame = try XCTUnwrap(CGImageSourceCreateImageAtIndex(saved, 0, nil))
        let expected = settings.aspectRatio.outputDimensions(
            source: PixelDimensions(width: 2_160, height: 3_840),
            shortEdge: 480
        )
        XCTAssertEqual(frame.width, expected.width)
        XCTAssertEqual(frame.height, expected.height)

        var plainConfiguration = OverlayConfiguration.preset(.runningFocus)
        for index in plainConfiguration.elements.indices {
            plainConfiguration.elements[index].isVisible = false
        }
        let plainOutput = directory.appendingPathComponent("原画帧.png")
        var plainRequest = withOverlay
        plainRequest.outputURL = plainOutput
        plainRequest.overlay = plainConfiguration
        try VideoFrameSnapshotter().capture(plainRequest, at: snapshotSecond)
        XCTAssertNotEqual(
            try Data(contentsOf: output),
            try Data(contentsOf: plainOutput),
            "带蒙层的截图不应和纯视频帧相同"
        )

        let defaultOutput = directory.appendingPathComponent("默认不带数据层.png")
        var defaultRequest = withOverlay
        defaultRequest.outputURL = defaultOutput
        try VideoFrameSnapshotter().capture(defaultRequest, at: snapshotSecond)
        XCTAssertEqual(
            try Data(contentsOf: defaultOutput),
            try Data(contentsOf: plainOutput),
            "默认截图即使配置了可见数据图层，也只应保存视频画面"
        )

        let letterboxedOutput = directory.appendingPathComponent("竖屏留黑.png")
        var letterboxedRequest = plainRequest
        letterboxedRequest.outputURL = letterboxedOutput
        letterboxedRequest.rotation = .none
        try VideoFrameSnapshotter().capture(letterboxedRequest, at: snapshotSecond)
        let letterboxedSource = try XCTUnwrap(
            CGImageSourceCreateWithURL(letterboxedOutput as CFURL, nil)
        )
        let letterboxed = try XCTUnwrap(
            CGImageSourceCreateImageAtIndex(letterboxedSource, 0, nil)
        )
        XCTAssertEqual(letterboxed.width, expected.width)
        XCTAssertEqual(letterboxed.height, expected.height)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let letterboxedImage = CIImage(cgImage: letterboxed)
        for (index, y) in [0, expected.height / 2].enumerated() {
            var pixels = [UInt8](repeating: 0, count: 4)
            context.render(
                letterboxedImage,
                toBitmap: &pixels,
                rowBytes: 4,
                bounds: CGRect(x: expected.width / 2, y: y, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: colorSpace
            )
            if index == 0 {
                XCTAssertEqual(Array(pixels.prefix(3)), [0, 0, 0])
            } else {
                XCTAssertTrue(pixels.prefix(3).contains { $0 > 20 })
            }
        }
        XCTAssertThrowsError(try VideoFrameSnapshotter().capture(
            withOverlay,
            at: snapshotSecond
        )) { error in
            XCTAssertEqual(error as? VideoFrameSnapshotError, .outputExists)
        }
        XCTAssertThrowsError(try VideoFrameSnapshotter().capture(
            plainRequest,
            at: .nan
        )) { error in
            XCTAssertEqual(error as? VideoFrameSnapshotError, .invalidTime)
        }
    }

    func test没有运动数据时仍可按原画幅保存视频截图() throws {
        let input = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("demo/DJI_20261002111832_0087_D.MP4")
        guard FileManager.default.isReadableFile(atPath: input.path) else {
            throw XCTSkip("当前工作区没有大疆演示视频")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var overlay = OverlayConfiguration.preset(.runningFocus)
        for index in overlay.elements.indices {
            overlay.elements[index].isVisible = false
        }
        let output = directory.appendingPathComponent("原始画幅.png")
        let request = VideoExportRequest(
            inputURL: input,
            outputURL: output,
            videoStart: nil,
            timeOffset: 0,
            overlay: overlay,
            activitySamples: [],
            activityStart: nil,
            settings: ExportSettings(maximumHeight: 480, aspectRatio: .source)
        )

        try VideoFrameSnapshotter().capture(request, at: 0)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 854)
        XCTAssertEqual(image.height, 480)
    }
}
