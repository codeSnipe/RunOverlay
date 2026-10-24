import AVFoundation
import CoreGraphics
import Foundation

public enum VideoMetadataReaderError: LocalizedError {
    case missingVideoTrack
    case invalidDuration

    public var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            RunOverlayLocalization.text("error.noVideoTrack")
        case .invalidDuration:
            RunOverlayLocalization.text("error.invalidDuration")
        }
    }
}

public struct VideoMetadataReader: Sendable {
    public init() {}

    public func read(from url: URL) async throws -> VideoAssetMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        guard let videoTrack = videoTracks.first else {
            throw VideoMetadataReaderError.missingVideoTrack
        }

        guard duration.isNumeric, duration.seconds > 0 else {
            throw VideoMetadataReaderError.invalidDuration
        }

        let size = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let metadata = try await asset.load(.commonMetadata)
        let displayedSize = size.applying(transform)
        let dimensions = PixelDimensions(
            width: Int(abs(displayedSize.width).rounded()),
            height: Int(abs(displayedSize.height).rounded())
        )
        let containerCapturedAt = await creationDate(from: metadata)
        let fileNameCapturedAt = VideoTimeResourceReader().capturedAt(from: url)
        let capturedAt = containerCapturedAt ?? fileNameCapturedAt
        let captureTimeSource: VideoCaptureTimeSource? = containerCapturedAt != nil
            ? .container : (fileNameCapturedAt != nil ? .fileName : nil)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

        return VideoAssetMetadata(
            durationSeconds: duration.seconds,
            dimensions: dimensions,
            frameRate: Double(frameRate),
            capturedAt: capturedAt,
            captureTimeSource: captureTimeSource,
            hasAudio: !audio.isEmpty,
            container: url.pathExtension.uppercased(),
            fileSizeBytes: fileSize
        )
    }

    private func creationDate(from metadata: [AVMetadataItem]) async -> Date? {
        let item = metadata.first {
            $0.identifier == .commonIdentifierCreationDate
        }
        guard let item, let value = try? await item.load(.stringValue) else {
            return nil
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return wholeSeconds.date(from: value)
    }
}
