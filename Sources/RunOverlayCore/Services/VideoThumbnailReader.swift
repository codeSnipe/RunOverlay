@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

public struct VideoThumbnailReader: Sendable {
    public init() {}

    public func read(from url: URL, at seconds: TimeInterval = 0.5) throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        return try generator.copyCGImage(
            at: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
            actualTime: nil
        )
    }
}
