import Foundation

public struct VideoOutputPlan: Equatable, Sendable {
    public let rotation: VideoRotation
    public let sourceDimensions: PixelDimensions
    public let rotatedDimensions: PixelDimensions
    public let outputDimensions: PixelDimensions
    public let aspectRatio: ExportAspectRatio
    public let shortEdge: Int
    public let hasLetterboxing: Bool
    public let needsUpscaling: Bool

    public var needsAttention: Bool {
        hasLetterboxing
    }

    public init(video: VideoItem, defaults: ExportSettings) {
        rotation = video.rotation
        sourceDimensions = video.metadata.dimensions
        rotatedDimensions = rotation.dimensions(afterRotating: sourceDimensions)
        aspectRatio = defaults.aspectRatio
        shortEdge = defaults.maximumHeight
        outputDimensions = aspectRatio.outputDimensions(
            source: rotatedDimensions,
            shortEdge: shortEdge
        )
        let sourceRatio = Double(rotatedDimensions.width) /
            Double(max(rotatedDimensions.height, 1))
        let targetRatio = Double(outputDimensions.width) /
            Double(max(outputDimensions.height, 1))
        hasLetterboxing = abs(sourceRatio / targetRatio - 1) > 0.01
        let fitScale = min(
            Double(outputDimensions.width) / Double(max(rotatedDimensions.width, 1)),
            Double(outputDimensions.height) / Double(max(rotatedDimensions.height, 1))
        )
        needsUpscaling = fitScale > 1.001
    }
}
