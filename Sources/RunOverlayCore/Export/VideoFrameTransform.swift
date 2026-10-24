import CoreImage
import Foundation

enum VideoFrameTransform {
    static func transformed(_ image: CIImage, by transform: CGAffineTransform) -> CIImage {
        let transformed = image.transformed(by: transform)
        let extent = transformed.extent
        return transformed.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        )
    }

    static func rotated(_ image: CIImage, by rotation: VideoRotation) -> CIImage {
        guard rotation != .none else { return image }
        let radians = CGFloat(rotation.rawValue) * .pi / 180
        let rotated = image.transformed(by: CGAffineTransform(rotationAngle: -radians))
        let extent = rotated.extent
        return rotated.transformed(by: CGAffineTransform(
            translationX: -extent.minX,
            y: -extent.minY
        ))
    }

    static func fitted(_ image: CIImage, renderSize: CGSize) -> CIImage {
        let sourceExtent = image.extent
        let sourceWidth = max(sourceExtent.width, 1)
        let sourceHeight = max(sourceExtent.height, 1)
        let scale = min(
            renderSize.width / sourceWidth,
            renderSize.height / sourceHeight
        )
        let scaledImage = image.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        let scaledExtent = scaledImage.extent
        let offsetX = (renderSize.width - scaledExtent.width) / 2 -
            scaledExtent.minX
        let offsetY = (renderSize.height - scaledExtent.height) / 2 -
            scaledExtent.minY
        return scaledImage.transformed(
            by: CGAffineTransform(translationX: offsetX, y: offsetY)
        )
    }
}
