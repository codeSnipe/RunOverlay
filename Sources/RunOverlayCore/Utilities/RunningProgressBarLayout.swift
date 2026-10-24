import CoreGraphics
import Foundation

/// 进度条在预览和导出中使用相同的轨道与填充区域。
public struct RunningProgressBarLayout: Sendable {
    public static let labelHeightFraction = 0.65

    public let track: CGRect
    public let fill: CGRect
    public let labels: CGRect
    public let currentLabel: CGRect

    public init(
        in bounds: CGRect,
        progress: Double?,
        originAtTop: Bool = true
    ) {
        let trackHeight = max(1, bounds.height * 0.15)
        let horizontalInset = max(1, bounds.width * 0.02)
        let topTrack = CGRect(
            x: bounds.minX + horizontalInset,
            y: bounds.minY + bounds.height * 0.47,
            width: max(0, bounds.width - horizontalInset * 2),
            height: trackHeight
        )
        let topLabels = CGRect(
            x: topTrack.minX,
            y: bounds.minY + bounds.height * 0.72,
            width: topTrack.width,
            height: bounds.height * 0.23
        )
        let topCurrentLabel = CGRect(
            x: topTrack.minX,
            y: bounds.minY + bounds.height * 0.08,
            width: topTrack.width,
            height: bounds.height * 0.28
        )
        func oriented(_ rect: CGRect) -> CGRect {
            guard !originAtTop else { return rect }
            return CGRect(
                x: rect.minX,
                y: bounds.minY + bounds.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        }
        track = oriented(topTrack)
        labels = oriented(topLabels)
        currentLabel = oriented(topCurrentLabel)

        let fraction = progress.flatMap { $0.isFinite ? $0 : nil }
            .map { min(max($0, 0), 1) } ?? 0
        let fillWidth = fraction > 0
            ? min(track.width, max(trackHeight, track.width * fraction))
            : 0
        fill = CGRect(
            x: track.minX,
            y: track.minY,
            width: fillWidth,
            height: track.height
        )
    }

    public func currentLabelCenterX(forTextWidth textWidth: CGFloat) -> CGFloat {
        let halfWidth = min(max(0, textWidth) / 2, currentLabel.width / 2)
        return min(
            max(track.minX + fill.width, currentLabel.minX + halfWidth),
            currentLabel.maxX - halfWidth
        )
    }
}
