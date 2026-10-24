import CoreGraphics
import Foundation

/// 与封面编辑器的文字选框使用相同范围，供单击空白时判断是否取消选择。
public struct CoverTextHitTester: Sendable {
    public init() {}

    public func layerID(
        at point: CGPoint,
        in size: CGSize,
        layers: [CoverTextLayer]
    ) -> UUID? {
        guard size.width > 1, size.height > 1 else { return nil }
        let composer = CoverComposer()
        for layer in layers.reversed() where !layer.text.isEmpty {
            let frame = composer.textFrame(of: layer, imageSize: size)
            guard frame.width > 0, frame.height > 0 else { continue }
            let rect = CGRect(
                x: frame.minX * size.width - 6,
                y: frame.minY * size.height - 6,
                width: frame.width * size.width + 12,
                height: frame.height * size.height + 12
            )
            let radians = -layer.rotationDegrees * .pi / 180
            let dx = point.x - rect.midX
            let dy = point.y - rect.midY
            let local = CGPoint(
                x: rect.midX + dx * cos(radians) - dy * sin(radians),
                y: rect.midY + dx * sin(radians) + dy * cos(radians)
            )
            if rect.contains(local) { return layer.id }
        }
        return nil
    }
}
