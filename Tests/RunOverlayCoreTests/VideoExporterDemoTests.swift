import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import RunOverlayCore

final class VideoExporterDemoTests: XCTestCase {
    func test实际视频旋转九十度后竖屏导出没有方向黑边() async throws {
        guard ProcessInfo.processInfo.environment["RUNOVERLAY_ROTATION_EXPORT"] == "1" else {
            throw XCTSkip("仅在明确开启旋转导出验证时执行")
        }
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let inputURL = projectDirectory.appendingPathComponent(
            "demo/DJI_20261002111755_0086_D.MP4"
        )
        guard FileManager.default.isReadableFile(atPath: inputURL.path) else {
            throw XCTSkip("当前工作区没有演示视频")
        }
        let outputDirectory = projectDirectory.appendingPathComponent(
            ".build/RotationSmoke-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let outputURL = outputDirectory.appendingPathComponent("竖屏旋转验证.mp4")
        let asset = AVURLAsset(url: inputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let sourceSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let displayedSize = sourceSize.applying(preferredTransform)
        let sourceWidth = Int(abs(displayedSize.width).rounded())
        let sourceHeight = Int(abs(displayedSize.height).rounded())
        XCTAssertGreaterThan(sourceWidth, sourceHeight)
        let targetShortEdge = 480
        let expected = ExportAspectRatio.portrait9x16.outputDimensions(
            source: PixelDimensions(width: sourceHeight, height: sourceWidth),
            shortEdge: targetShortEdge
        )
        var overlay = OverlayConfiguration.preset(.runningFocus)
        overlay.elements = [OverlayElementConfiguration(
            kind: .clockTime,
            frame: NormalizedRect(x: 0.1, y: 0.05, width: 0.8, height: 0.08),
            clockDisplay: .time
        )]

        let request = VideoExportRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            videoStart: Date(timeIntervalSince1970: 1_800_000_000),
            timeOffset: 0,
            overlay: overlay,
            activitySamples: [],
            activityStart: nil,
            settings: ExportSettings(
                maximumHeight: targetShortEdge,
                aspectRatio: .portrait9x16
            ),
            rotation: .clockwise90
        )
        let exporter = await VideoExporter()
        try await exporter.export(request) { _ in }
        let output = AVURLAsset(url: outputURL)
        let outputTracks = try await output.loadTracks(withMediaType: .video)
        XCTAssertEqual(outputTracks.count, 1)
        let generator = AVAssetImageGenerator(asset: output)
        generator.appliesPreferredTrackTransform = true
        let frame = try generator.copyCGImage(
            at: CMTime(seconds: 1, preferredTimescale: 600),
            actualTime: nil
        )
        XCTAssertEqual(frame.width, expected.width)
        XCTAssertEqual(frame.height, expected.height)

        let image = CIImage(cgImage: frame)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let overlayRegion = CGRect(
            x: CGFloat(frame.width) * 0.1,
            y: CGFloat(frame.height) * 0.87,
            width: CGFloat(frame.width) * 0.8,
            height: CGFloat(frame.height) * 0.08
        )
        let frameBytes = try XCTUnwrap(
            context.createCGImage(image, from: overlayRegion)?.dataProvider?.data as Data?
        )
        XCTAssertFalse(frameBytes.isEmpty)
        try savePNG(
            frame,
            to: outputDirectory.appendingPathComponent("旋转后首帧.png")
        )
        print("旋转导出视觉检查：\(outputDirectory.path)")
    }

    func test演示视频实际导出时钟图层() async throws {
        guard ProcessInfo.processInfo.environment["RUNOVERLAY_DEMO_EXPORT"] == "1" else {
            throw XCTSkip("仅在明确开启演示视频导出验证时执行")
        }

        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let inputURL = projectDirectory.appendingPathComponent(
            "demo/DJI_20261002111755_0086_D.MP4"
        )
        let timeResourceURL = projectDirectory.appendingPathComponent(
            "demo/DJI_20261002111755_0086_D.LRF"
        )
        guard FileManager.default.isReadableFile(atPath: inputURL.path) else {
            throw XCTSkip("当前工作区没有演示视频")
        }

        let outputDirectory = projectDirectory
            .appendingPathComponent(".build/ClockLayerSmoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let outputURL = outputDirectory.appendingPathComponent("时钟蒙层验证.mp4")
        var overlay = OverlayConfiguration.preset(.sport)
        overlay.elements = [OverlayConfiguration.clockTimeElement()]
        let request = VideoExportRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            videoStart: VideoTimeResourceReader().capturedAt(from: timeResourceURL),
            timeOffset: 0,
            overlay: overlay,
            activitySamples: [],
            activityStart: nil,
            settings: ExportSettings(maximumHeight: 480)
        )
        XCTAssertNotNil(request.videoStart)

        let exporter = await VideoExporter()
        try await exporter.export(request) { _ in }

        let output = AVURLAsset(url: outputURL)
        let duration = try await output.load(.duration)
        let tracks = try await output.loadTracks(withMediaType: .video)
        XCTAssertGreaterThan(duration.seconds, 8)
        XCTAssertFalse(tracks.isEmpty)

        let generator = AVAssetImageGenerator(asset: output)
        generator.appliesPreferredTrackTransform = true
        let first = try generator.copyCGImage(
            at: CMTime(seconds: 0.2, preferredTimescale: 600),
            actualTime: nil
        )
        let second = try generator.copyCGImage(
            at: CMTime(seconds: 1.4, preferredTimescale: 600),
            actualTime: nil
        )
        XCTAssertEqual(first.width, second.width)
        XCTAssertEqual(first.height, second.height)

        try savePNG(first, to: outputDirectory.appendingPathComponent("第1帧.png"))
        try savePNG(second, to: outputDirectory.appendingPathComponent("第2帧.png"))
        let timestamp = try XCTUnwrap(request.videoStart)
        let sample = ActivitySample(
            timestamp: timestamp,
            coordinate: GeoCoordinate(latitude: 31.2, longitude: 121.4),
            distanceMeters: 2_345,
            speedMetersPerSecond: 3.4,
            heartRate: 151
        )
        let layout = try XCTUnwrap(
            OverlayFrameRenderer().render(
                size: CGSize(width: first.width, height: first.height),
                configuration: .preset(.sport),
                sample: sample,
                route: [
                    GeoCoordinate(latitude: 31.2, longitude: 121.4),
                    GeoCoordinate(latitude: 31.201, longitude: 121.401),
                    GeoCoordinate(latitude: 31.202, longitude: 121.402)
                ],
                activityStart: timestamp.addingTimeInterval(-600),
                clockTime: timestamp
            )
        )
        let fullFrame = try XCTUnwrap(
            CIContext().createCGImage(
                layout.composited(over: CIImage(cgImage: first)),
                from: layout.extent
            )
        )
        try savePNG(
            fullFrame,
            to: outputDirectory.appendingPathComponent("默认布局预览.png")
        )
        let activityURL = projectDirectory.appendingPathComponent(
            "demo/480745612738855213.fit"
        )
        if FileManager.default.isReadableFile(atPath: activityURL.path) {
            let activity = try ActivityParser().parse(from: activityURL)
            XCTAssertTrue(activity.availableChannels.contains(.ascent))
            let runningSample = ActivityTimeline().sample(
                at: timestamp.addingTimeInterval(2),
                in: activity.samples
            )
            XCTAssertNotNil(runningSample)
            let runningRoute = activity.samples.compactMap(\.coordinate)
            let sourceGenerator = AVAssetImageGenerator(
                asset: AVURLAsset(url: inputURL)
            )
            sourceGenerator.appliesPreferredTrackTransform = true
            let sourceFrame = try sourceGenerator.copyCGImage(
                at: CMTime(seconds: 0.2, preferredTimescale: 600),
                actualTime: nil
            )
            let sourceImage = CIImage(cgImage: sourceFrame)
            let context = CIContext()

            for preset in [
                OverlayTemplatePreset.track,
                .finishLine,
                .trail,
                .nightRun,
                .stadiumLive
            ] {
                for (suffix, dimensions) in [
                    ("横屏", CGSize(width: 854, height: 480)),
                    ("竖屏", CGSize(width: 270, height: 480))
                ] {
                    let scale = min(
                        dimensions.width / sourceImage.extent.width,
                        dimensions.height / sourceImage.extent.height
                    )
                    let scaled = sourceImage.transformed(
                        by: CGAffineTransform(scaleX: scale, y: scale)
                    )
                    let aligned = scaled.transformed(
                        by: CGAffineTransform(
                            translationX: (dimensions.width - scaled.extent.width) / 2,
                            y: (dimensions.height - scaled.extent.height) / 2
                        )
                    )
                    let canvas = CGRect(origin: .zero, size: dimensions)
                    let background = CIImage(color: .black).cropped(to: canvas)
                    let video = aligned.composited(over: background)
                        .cropped(to: canvas)
                    let overlay = try XCTUnwrap(
                        OverlayFrameRenderer().render(
                            size: dimensions,
                            configuration: .preset(preset),
                            sample: runningSample,
                            route: runningRoute,
                            activityStart: activity.timeRange.start,
                            clockTime: timestamp
                        )
                    )
                    let preview = try XCTUnwrap(
                        context.createCGImage(
                            overlay.composited(over: video),
                            from: canvas
                        )
                    )
                    try savePNG(
                        preview,
                        to: outputDirectory.appendingPathComponent(
                            "\(preset.rawValue)-\(suffix).png"
                        )
                    )
                }
            }

            let portraitOutputURL = outputDirectory.appendingPathComponent(
                "竖屏跑步蒙层验证.mp4"
            )
            try await exporter.export(
                VideoExportRequest(
                    inputURL: inputURL,
                    outputURL: portraitOutputURL,
                    videoStart: timestamp,
                    timeOffset: 0,
                    overlay: .preset(.track),
                    activitySamples: activity.samples,
                    activityStart: activity.timeRange.start,
                    settings: ExportSettings(
                        maximumHeight: 270,
                        aspectRatio: .portrait9x16
                    )
                )
            ) { _ in }
            let portraitAsset = AVURLAsset(url: portraitOutputURL)
            let portraitTracks = try await portraitAsset.loadTracks(
                withMediaType: .video
            )
            XCTAssertEqual(portraitTracks.count, 1)
            let portraitGenerator = AVAssetImageGenerator(asset: portraitAsset)
            portraitGenerator.appliesPreferredTrackTransform = true
            let portraitFrame = try portraitGenerator.copyCGImage(
                at: CMTime(seconds: 2, preferredTimescale: 600),
                actualTime: nil
            )
            XCTAssertEqual(portraitFrame.width, 270)
            XCTAssertEqual(portraitFrame.height, 480)
            try savePNG(
                portraitFrame,
                to: outputDirectory.appendingPathComponent("竖屏跑步视频实际帧.png")
            )

            let stadiumOutputURL = outputDirectory.appendingPathComponent(
                "赛场实况实际导出.mp4"
            )
            try await exporter.export(
                VideoExportRequest(
                    inputURL: inputURL,
                    outputURL: stadiumOutputURL,
                    videoStart: timestamp,
                    timeOffset: 0,
                    overlay: .preset(.stadiumLive),
                    activitySamples: activity.samples,
                    activityStart: activity.timeRange.start,
                    settings: ExportSettings(
                        maximumHeight: 480,
                        videoTextLanguage: .english
                    )
                )
            ) { _ in }
            let stadiumAsset = AVURLAsset(url: stadiumOutputURL)
            let stadiumGenerator = AVAssetImageGenerator(asset: stadiumAsset)
            stadiumGenerator.appliesPreferredTrackTransform = true
            let stadiumFrame = try stadiumGenerator.copyCGImage(
                at: CMTime(seconds: 2, preferredTimescale: 600),
                actualTime: nil
            )
            XCTAssertEqual(stadiumFrame.width, 854)
            XCTAssertEqual(stadiumFrame.height, 480)
            try savePNG(
                stadiumFrame,
                to: outputDirectory.appendingPathComponent("赛场实况实际导出帧.png")
            )
        }
        print("时钟蒙层演示导出：\(outputURL.path)")
    }

    private func savePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
