import CoreGraphics
import Foundation

public enum OverlayResizeHandle: CaseIterable, Hashable, Sendable {
    case topLeading
    case top
    case topTrailing
    case trailing
    case bottom
    case bottomLeading
    case bottomTrailing
    case leading

    public var anchor: CGPoint {
        switch self {
        case .topLeading: CGPoint(x: -1, y: -1)
        case .top: CGPoint(x: 0, y: -1)
        case .topTrailing: CGPoint(x: 1, y: -1)
        case .trailing: CGPoint(x: 1, y: 0)
        case .bottom: CGPoint(x: 0, y: 1)
        case .bottomLeading: CGPoint(x: -1, y: 1)
        case .bottomTrailing: CGPoint(x: 1, y: 1)
        case .leading: CGPoint(x: -1, y: 0)
        }
    }
}

public struct OverlayHitTarget: Equatable, Sendable {
    public var elementID: UUID
    public var handle: OverlayResizeHandle?

    public init(elementID: UUID, handle: OverlayResizeHandle? = nil) {
        self.elementID = elementID
        self.handle = handle
    }
}

public enum OverlayHitTester {
    private static let borderWidth: CGFloat = 16
    private static let outsideAllowance: CGFloat = 6

    public static func resizeHandle(
        at point: CGPoint,
        in frame: CGRect
    ) -> OverlayResizeHandle? {
        guard frame.insetBy(dx: -outsideAllowance, dy: -outsideAllowance).contains(point) else {
            return nil
        }
        return borderHandle(at: point, for: frame)
    }

    public static func target(
        at point: CGPoint,
        in canvasSize: CGSize,
        elements: [OverlayElementConfiguration],
        selectedElementID: UUID?
    ) -> OverlayHitTarget? {
        // 已选边框允许从边框外侧几像素开始拖，且优先于相邻卡片。
        if let selected = elements.first(where: {
            $0.id == selectedElementID && $0.isVisible
        }) {
            let frame = frame(for: selected, in: canvasSize)
            if let handle = resizeHandle(at: point, in: frame) {
                return OverlayHitTarget(
                    elementID: selected.id,
                    handle: handle
                )
            }
        }

        for element in elements.reversed() where element.isVisible {
            let frame = frame(for: element, in: canvasSize)
            guard frame.contains(point) else {
                continue
            }
            return OverlayHitTarget(elementID: element.id)
        }
        return nil
    }

    private static func frame(
        for element: OverlayElementConfiguration,
        in canvasSize: CGSize
    ) -> CGRect {
        CGRect(
            x: CGFloat(element.frame.x) * canvasSize.width,
            y: CGFloat(element.frame.y) * canvasSize.height,
            width: max(1, CGFloat(element.frame.width) * canvasSize.width),
            height: max(1, CGFloat(element.frame.height) * canvasSize.height)
        )
    }

    private static func borderHandle(
        at point: CGPoint,
        for frame: CGRect
    ) -> OverlayResizeHandle? {
        let left = abs(point.x - frame.minX)
        let right = abs(point.x - frame.maxX)
        let top = abs(point.y - frame.minY)
        let bottom = abs(point.y - frame.maxY)
        let nearLeft = left <= borderWidth && left <= right
        let nearRight = right <= borderWidth && right < left
        let nearTop = top <= borderWidth && top <= bottom
        let nearBottom = bottom <= borderWidth && bottom < top

        switch (nearTop, nearBottom, nearLeft, nearRight) {
        case (true, _, true, _): return .topLeading
        case (true, _, _, true): return .topTrailing
        case (_, true, true, _): return .bottomLeading
        case (_, true, _, true): return .bottomTrailing
        case (true, _, _, _): return .top
        case (_, true, _, _): return .bottom
        case (_, _, true, _): return .leading
        case (_, _, _, true): return .trailing
        default: return nil
        }
    }
}
