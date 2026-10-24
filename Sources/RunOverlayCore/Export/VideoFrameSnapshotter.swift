@preconcurrency import AVFoundation
import CoreImage
import CoreGraphics
import Foundation

public enum VideoFrameSnapshotError: LocalizedError, Equatable {
    case invalidTime
    case outputExists
    case imageCreationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidTime:
            RunOverlayLocalization.text("error.snapshot.invalidTime")
        case .outputExists:
            RunOverlayLocalization.text("error.outputExists")
        case .imageCreationFailed:
            RunOverlayLocalization.text("error.snapshot.imageCreationFailed")
        }
    }
}

public struct VideoFrameSnapshotter: Sendable {
    public init() {}

    /// 优先使用播放器实际停住的时间；只有播放器时间不可用时才回退到时间轴。
    public static func captureTime(
        playerTime: TimeInterval?,
        fallbackTime: TimeInterval,
        duration: TimeInterval,
        frameRate: Double
    ) -> TimeInterval {
        let validPlayerTime = playerTime.flatMap { $0.isFinite ? $0 : nil }
        let requestedTime = validPlayerTime ?? (fallbackTime.isFinite ? fallbackTime : 0)
        let safeFrameRate = frameRate.isFinite && frameRate > 0 ? frameRate : 30
        let safeDuration = duration.isFinite ? max(0, duration) : 0
        return min(max(0, requestedTime), max(0, safeDuration - 1 / safeFrameRate))
    }

    /// 截取指定播放位置的一帧，按视频导出的画幅和旋转生成 PNG，按需叠加运动数据。
    public func capture(
        _ request: VideoExportRequest,
        at seconds: TimeInterval,
        includeDataLayer: Bool = false
    ) throws {
        guard seconds.isFinite, seconds >= 0 else {
            throw VideoFrameSnapshotError.invalidTime
        }
        guard !FileManager.default.fileExists(atPath: request.outputURL.path) else {
            throw VideoFrameSnapshotError.outputExists
        }
        let image = try renderImage(request, at: seconds, includeDataLayer: includeDataLayer)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let data = CIContext().pngRepresentation(
                of: CIImage(cgImage: image),
                format: .RGBA8,
                colorSpace: colorSpace
              ) else {
            throw VideoFrameSnapshotError.imageCreationFailed
        }
        try data.write(to: request.outputURL, options: .withoutOverwriting)
    }

    public func renderImage(
        _ request: VideoExportRequest,
        at seconds: TimeInterval,
        includeDataLayer: Bool = false
    ) throws -> CGImage {
        guard seconds.isFinite, seconds >= 0 else {
            throw VideoFrameSnapshotError.invalidTime
        }
        let asset = AVURLAsset(url: request.inputURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var actualTime = CMTime.invalid
        let frame = try generator.copyCGImage(
            at: CMTime(seconds: seconds, preferredTimescale: 60_000),
            actualTime: &actualTime
        )

        let source = PixelDimensions(width: frame.width, height: frame.height)
        let rotatedDimensions = request.rotation.dimensions(afterRotating: source)
        let outputDimensions = request.settings.aspectRatio.outputDimensions(
            source: rotatedDimensions,
            shortEdge: request.settings.maximumHeight
        )
        let renderSize = CGSize(
            width: outputDimensions.width,
            height: outputDimensions.height
        )
        let extent = CGRect(origin: .zero, size: renderSize)
        let transformed = VideoFrameTransform.fitted(
            VideoFrameTransform.rotated(CIImage(cgImage: frame), by: request.rotation),
            renderSize: renderSize
        )
        let background = CIImage(color: .black).cropped(to: extent)
        var image = transformed.composited(over: background).cropped(to: extent)

        if includeDataLayer {
            let frameSeconds = actualTime.isNumeric ? actualTime.seconds : seconds
            let timestamp = request.videoStart?.addingTimeInterval(
                request.timeOffset + frameSeconds
            )
            let sample = timestamp.flatMap {
                ActivityTimeline().sample(at: $0, in: request.activitySamples)
            }
            let activityProgress = ActivityProgressCalculator(
                samples: request.activitySamples
            ).progress(for: sample)
            if let overlay = OverlayFrameRenderer().render(
                size: renderSize,
                configuration: request.overlay,
                sample: sample,
                activityProgress: activityProgress,
                route: request.activitySamples.compactMap(\.coordinate),
                elevationProfile: ElevationProfile(samples: request.activitySamples),
                activityStart: request.activityStart,
                clockTime: timestamp,
                videoTextLanguage: request.settings.videoTextLanguage
            ) {
                image = overlay.composited(over: image).cropped(to: extent)
            }
        }

        guard let renderedImage = CIContext().createCGImage(image, from: extent) else {
            throw VideoFrameSnapshotError.imageCreationFailed
        }
        return renderedImage
    }
}
