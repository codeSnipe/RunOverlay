import CoreGraphics
import Foundation

public enum RouteProjection {
    public static func coreGraphicsPoints(
        for coordinates: [GeoCoordinate],
        in rect: CGRect,
        using boundsCoordinates: [GeoCoordinate]? = nil
    ) -> [CGPoint] {
        points(for: coordinates, in: rect, using: boundsCoordinates).map { point in
            CGPoint(x: point.x, y: rect.minY + rect.maxY - point.y)
        }
    }

    public static func points(
        for coordinates: [GeoCoordinate],
        in rect: CGRect,
        using boundsCoordinates: [GeoCoordinate]? = nil
    ) -> [CGPoint] {
        let bounds = boundsCoordinates ?? coordinates
        guard
            !coordinates.isEmpty,
            !bounds.isEmpty,
            rect.width > 0,
            rect.height > 0
        else {
            return []
        }

        let averageLatitude = bounds.reduce(0.0) { $0 + $1.latitude } /
            Double(bounds.count)
        let longitudeScale = cos(averageLatitude * .pi / 180)
        let projectedBounds = bounds.map {
            (x: $0.longitude * longitudeScale, y: $0.latitude)
        }
        let minimumX = projectedBounds.map(\.x).min() ?? 0
        let maximumX = projectedBounds.map(\.x).max() ?? 1
        let minimumY = projectedBounds.map(\.y).min() ?? 0
        let maximumY = projectedBounds.map(\.y).max() ?? 1
        let rangeX = max(maximumX - minimumX, 0.000_001)
        let rangeY = max(maximumY - minimumY, 0.000_001)

        // 使用同一比例缩放经纬投影坐标，保留轨迹真实的长宽比例。
        let scale = min(rect.width / rangeX, rect.height / rangeY)
        let drawnWidth = rangeX * scale
        let drawnHeight = rangeY * scale
        let offsetX = rect.minX + (rect.width - drawnWidth) / 2
        let offsetY = rect.minY + (rect.height - drawnHeight) / 2

        return coordinates.map { coordinate in
            CGPoint(
                x: offsetX + (coordinate.longitude * longitudeScale - minimumX) * scale,
                y: offsetY + (maximumY - coordinate.latitude) * scale
            )
        }
    }
}
