@preconcurrency import AVFoundation
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import RunOverlayCore

@MainActor
final class VideoExporterRealDJITests: XCTestCase {
    /// 显式开启后用真实大疆素材截取短片导出，避免日常单元测试反复编码 4K 视频。
    func test两段真实大疆素材的运动蒙层音频和画幅() async throws {
        guard ProcessInfo.processInfo.environment["RUNOVERLAY_DJI_EXPORT"] == "1" else {
            throw XCTSkip("仅在明确开启真实大疆导出验收时执行")
        }
        let demo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("demo", isDirectory: true)
        let activityFile = demo.appendingPathComponent("480745612738855213.fit")
        let names = [
            "DJI_20261002111755_0086_D",
            "DJI_20261002111832_0087_D"
        ]
        guard FileManager.default.isReadableFile(atPath: activityFile.path),
              names.allSatisfy({
                  FileManager.default.isReadableFile(
                      atPath: demo.appendingPathComponent("\($0).MP4").path
                  )
              }) else {
            throw XCTSkip("当前工作区没有完整的两段大疆视频和 FIT 文件")
        }

        let activity = try ActivityParser().parse(from: activityFile)
        let outputDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/DJIExportValidation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        for (index, name) in names.enumerated() {
            let original = demo.appendingPathComponent("\(name).MP4")
            let metadata = try await VideoMetadataReader().read(from: original)
            let capturedAt = try XCTUnwrap(metadata.capturedAt)
            XCTAssertEqual(
                VideoActivityMatcher().match(
                    videoStart: capturedAt,
                    duration: metadata.durationSeconds,
                    activityRange: activity.timeRange
                ).status,
                .complete
            )
            let clipURL = outputDirectory.appendingPathComponent("\(name)-clip.mp4")
            try await makeShortClip(from: original, to: clipURL, duration: 3.2)
            let sourceAsset = AVURLAsset(url: clipURL)
            let expectedAudio = try await sourceAsset.loadTracks(withMediaType: .audio).count
            let rotation: VideoRotation = index == 0 ? .none : .clockwise90
            let aspect: ExportAspectRatio = index == 0
                ? .landscape16x9 : .portrait9x16
            let output = outputDirectory.appendingPathComponent("\(name)-overlay.mp4")
            let request = VideoExportRequest(
                inputURL: clipURL,
                outputURL: output,
                videoStart: capturedAt,
                timeOffset: 0,
                overlay: .preset(.runningFocus),
                activitySamples: activity.samples,
                activityStart: activity.timeRange.start,
                settings: ExportSettings(
                    maximumHeight: 480,
                    aspectRatio: aspect
                ),
                rotation: rotation
            )
            try await VideoExporter().export(request) { _ in }
            var plain = request
            for elementIndex in plain.overlay.elements.indices {
                plain.overlay.elements[elementIndex].isVisible = false
            }
            plain.outputURL = outputDirectory.appendingPathComponent("\(name)-plain.mp4")
            try await VideoExporter().export(plain) { _ in }

            let exported = AVURLAsset(url: output)
            let plainAsset = AVURLAsset(url: plain.outputURL)
            let duration = try await exported.load(.duration).seconds
            XCTAssertEqual(duration, 3.2, accuracy: 0.15)
            let videoTracks = try await exported.loadTracks(withMediaType: .video)
            XCTAssertEqual(videoTracks.count, 1)
            let outputAudio = try await exported.loadTracks(withMediaType: .audio)
            XCTAssertEqual(outputAudio.count, expectedAudio, name)

            let expected = aspect.outputDimensions(
                source: rotation.dimensions(afterRotating: metadata.dimensions),
                shortEdge: 480
            )
            var sampledDistances: [Double] = []
            var sampledCoordinates: [GeoCoordinate] = []
            for second in [0.5, 2.5] {
                let exportedFrame = try frame(in: exported, at: second)
                XCTAssertEqual(exportedFrame.width, expected.width)
                XCTAssertEqual(exportedFrame.height, expected.height)
                let plainFrame = try frame(in: plainAsset, at: second)
                XCTAssertEqual(plainFrame.width, exportedFrame.width)
                XCTAssertEqual(plainFrame.height, exportedFrame.height)
                let sample = ActivityTimeline().sample(
                    at: capturedAt.addingTimeInterval(second),
                    in: activity.samples
                )
                sampledCoordinates.append(try XCTUnwrap(
                    sample?.coordinate,
                    "\(name) 在 \(second) 秒缺少轨迹"
                ))
                sampledDistances.append(try XCTUnwrap(
                    sample?.distanceMeters,
                    "\(name) 在 \(second) 秒缺少距离"
                ))
                let routeFrame = try XCTUnwrap(
                    request.overlay.elements.first(where: { $0.kind == .route })?.frame
                )
                let routeDifferences = try distinctPixels(
                    exportedFrame,
                    plainFrame,
                    inside: routeFrame
                )
                XCTAssertGreaterThan(
                    routeDifferences, 130,
                    "\(name) 在 \(second) 秒导出的轨迹区域应明显区别于纯视频"
                )
            }
            XCTAssertGreaterThan(
                try XCTUnwrap(sampledDistances.last),
                try XCTUnwrap(sampledDistances.first),
                "\(name) 的运动里程应随着时间增加"
            )
            XCTAssertNotEqual(
                sampledCoordinates.first, sampledCoordinates.last,
                "\(name) 的当前轨迹点应随着时间移动"
            )

            let dataFrame = try frame(in: exported, at: 1.5)
            let plainFrame = try frame(in: plainAsset, at: 1.5)
            let differences = try distinctPixels(dataFrame, plainFrame)
            XCTAssertGreaterThan(
                differences, 500,
                "\(name) 导出帧与不含数据层的画面应有可见差异"
            )
            try savePNG(
                dataFrame,
                to: outputDirectory.appendingPathComponent("\(name)-蒙层验证.png")
            )
            print("大疆导出验收：\(output.path)，\(expected.displayText)，蒙层差异像素 \(differences)，音轨 \(outputAudio.count)")
        }
    }

    func test真实大疆视频导出的轨迹爬升曲线与当前位置() async throws {
        guard ProcessInfo.processInfo.environment["RUNOVERLAY_DJI_EXPORT"] == "1" else {
            throw XCTSkip("仅在明确开启真实大疆导出验收时执行")
        }
        let demo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("demo", isDirectory: true)
        let input = demo.appendingPathComponent("DJI_20261002111755_0086_D.MP4")
        let activityFile = demo.appendingPathComponent("480745612738855213.fit")
        guard FileManager.default.isReadableFile(atPath: input.path),
              FileManager.default.isReadableFile(atPath: activityFile.path) else {
            throw XCTSkip("当前工作区没有完整的大疆视频和 FIT 数据")
        }
        let activity = try ActivityParser().parse(from: activityFile)
        let metadata = try await VideoMetadataReader().read(from: input)
        let started = try XCTUnwrap(metadata.capturedAt)
        let outputDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/DJIElevationValidation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let clip = outputDirectory.appendingPathComponent("短片.mp4")
        try await makeShortClip(from: input, to: clip, duration: 3.2)
        let frame = NormalizedRect(x: 0.60, y: 0.18, width: 0.36, height: 0.24)
        var configuration = OverlayConfiguration.preset(.runningFocus)
        configuration.elements = [OverlayElementConfiguration(
            kind: .elevationProfile,
            frame: frame,
            backgroundOpacity: 0.32
        )]
        let request = VideoExportRequest(
            inputURL: clip,
            outputURL: outputDirectory.appendingPathComponent("轨迹爬升.mp4"),
            videoStart: started,
            timeOffset: 0,
            overlay: configuration,
            activitySamples: activity.samples,
            activityStart: activity.timeRange.start,
            settings: ExportSettings(maximumHeight: 480)
        )
        var withoutOverlay = request
        withoutOverlay.outputURL = outputDirectory.appendingPathComponent("原画.mp4")
        withoutOverlay.overlay.elements[0].isVisible = false
        try await VideoExporter().export(withoutOverlay) { _ in }
        try await VideoExporter().export(request) { _ in }

        let encoded = AVURLAsset(url: request.outputURL)
        let plain = AVURLAsset(url: withoutOverlay.outputURL)
        for second in [0.5, 2.5] {
            let rendered = try self.frame(in: encoded, at: second)
            let sourceFrame = try self.frame(in: plain, at: second)
            XCTAssertGreaterThan(
                try distinctPixels(rendered, sourceFrame, inside: frame),
                160,
                "曲线与累计爬升数值必须真正烧录进导出的视频"
            )
        }
        let snapshotter = VideoFrameSnapshotter()
        let withChartSnapshot = try snapshotter.renderImage(
            request,
            at: 1.5,
            includeDataLayer: true
        )
        let plainSnapshot = try snapshotter.renderImage(
            request,
            at: 1.5,
            includeDataLayer: false
        )
        XCTAssertGreaterThan(
            try distinctPixels(withChartSnapshot, plainSnapshot, inside: frame),
            160,
            "选中「包含数据层」的截图也必须显示爬升曲线"
        )
        let first = try self.frame(in: encoded, at: 0.5)
        let last = try self.frame(in: encoded, at: 2.5)
        try savePNG(
            first,
            to: outputDirectory.appendingPathComponent("轨迹爬升起点.png")
        )
        try savePNG(
            last,
            to: outputDirectory.appendingPathComponent("轨迹爬升终点.png")
        )
        print("轨迹爬升实片验收：\(request.outputURL.path)")
    }

    private func makeShortClip(
        from input: URL,
        to output: URL,
        duration: Double
    ) async throws {
        let asset = AVURLAsset(url: input)
        let session = try XCTUnwrap(
            AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        )
        session.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        session.outputURL = output
        session.outputFileType = .mp4
        let sessionBox = ValidationExportSessionBox(session: session)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                Task { @MainActor in
                    switch sessionBox.session.status {
                    case .completed:
                        continuation.resume()
                    case .failed:
                        continuation.resume(throwing:
                            sessionBox.session.error ?? CocoaError(.fileReadUnknown))
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    default:
                        continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    }
                }
            }
        }
    }

    private func frame(in asset: AVAsset, at seconds: Double) throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try generator.copyCGImage(
            at: CMTime(seconds: seconds, preferredTimescale: 600),
            actualTime: nil
        )
    }

    private func distinctPixels(
        _ first: CGImage,
        _ second: CGImage,
        inside normalized: NormalizedRect? = nil
    ) throws -> Int {
        XCTAssertEqual(first.width, second.width)
        XCTAssertEqual(first.height, second.height)
        let size = CGSize(width: first.width, height: first.height)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        func bytes(_ image: CGImage) -> [UInt8] {
            var pixels = [UInt8](repeating: 0, count: first.width * first.height * 4)
            pixels.withUnsafeMutableBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                context.render(
                    CIImage(cgImage: image),
                    toBitmap: baseAddress,
                    rowBytes: first.width * 4,
                    bounds: CGRect(origin: .zero, size: size),
                    format: .RGBA8,
                    colorSpace: colorSpace
                )
            }
            return pixels
        }
        let lhs = bytes(first)
        let rhs = bytes(second)
        let xRange: Range<Int>
        let yRange: Range<Int>
        if let normalized {
            let minimumX = max(0, Int(normalized.x * Double(first.width)))
            let maximumX = min(
                first.width,
                Int((normalized.x + normalized.width) * Double(first.width))
            )
            let minimumY = max(
                0,
                Int(normalized.y * Double(first.height))
            )
            let maximumY = min(
                first.height,
                Int((normalized.y + normalized.height) * Double(first.height))
            )
            xRange = minimumX..<maximumX
            yRange = minimumY..<maximumY
        } else {
            xRange = 0..<first.width
            yRange = 0..<first.height
        }
        var count = 0
        for y in yRange {
            for x in xRange {
                let offset = (y * first.width + x) * 4
                let difference = (0..<3).reduce(0) { total, channel in
                    total + abs(Int(lhs[offset + channel]) - Int(rhs[offset + channel]))
                }
                if difference > 75 { count += 1 }
            }
        }
        return count
    }

    private func savePNG(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}

@MainActor
private final class ValidationExportSessionBox {
    let session: AVAssetExportSession

    init(session: AVAssetExportSession) {
        self.session = session
    }
}
