import CoreGraphics
import XCTest
@testable import RunOverlayCore

final class RouteProjectionTests: XCTestCase {
    func test非正方形轨迹保持经纬投影比例并在视口中留白居中() {
        let route = [
            GeoCoordinate(latitude: 0, longitude: 0),
            GeoCoordinate(latitude: 0, longitude: 0.02),
            GeoCoordinate(latitude: 0.01, longitude: 0.02),
            GeoCoordinate(latitude: 0.01, longitude: 0)
        ]

        let points = RouteProjection.points(
            for: route,
            in: CGRect(x: 0, y: 0, width: 200, height: 200)
        )

        let width = (points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0)
        let height = (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0)
        let minimumY = points.map(\.y).min() ?? 0
        let maximumY = points.map(\.y).max() ?? 0

        XCTAssertEqual(width / height, 2, accuracy: 0.000_001)
        XCTAssertEqual(minimumY, 50, accuracy: 0.000_001)
        XCTAssertEqual(maximumY, 150, accuracy: 0.000_001)
    }

    func test当前位置和整条轨迹使用相同投影边界() {
        let route = [
            GeoCoordinate(latitude: 31.2, longitude: 121.4),
            GeoCoordinate(latitude: 31.205, longitude: 121.41),
            GeoCoordinate(latitude: 31.21, longitude: 121.4)
        ]
        let viewport = CGRect(x: 6, y: 6, width: 188, height: 88)

        let routePoints = RouteProjection.points(for: route, in: viewport)
        let currentPoint = RouteProjection.points(
            for: [route[1]],
            in: viewport,
            using: route
        )[0]

        XCTAssertEqual(currentPoint.x, routePoints[1].x, accuracy: 0.000_001)
        XCTAssertEqual(currentPoint.y, routePoints[1].y, accuracy: 0.000_001)
    }

    func test导出坐标按绘图原点翻转而不改变预览坐标() {
        let route = [
            GeoCoordinate(latitude: 30.0, longitude: 120.0),
            GeoCoordinate(latitude: 30.01, longitude: 120.01),
            GeoCoordinate(latitude: 30.02, longitude: 120.02)
        ]
        let rect = CGRect(x: 12, y: 37, width: 160, height: 100)
        let preview = RouteProjection.points(for: route, in: rect)
        let exported = RouteProjection.coreGraphicsPoints(for: route, in: rect)

        XCTAssertLessThan(preview[2].y, preview[0].y, "预览坐标越北越靠上")
        XCTAssertGreaterThan(exported[2].y, exported[0].y, "导出绘图坐标越北越靠上")
        for index in route.indices {
            XCTAssertEqual(exported[index].x, preview[index].x, accuracy: 0.000_001)
            XCTAssertEqual(
                exported[index].y,
                rect.minY + rect.maxY - preview[index].y,
                accuracy: 0.000_001
            )
        }

        let marker = RouteProjection.coreGraphicsPoints(
            for: [route[1]], in: rect, using: route
        )
        XCTAssertEqual(marker[0].x, exported[1].x, accuracy: 0.000_001)
        XCTAssertEqual(marker[0].y, exported[1].y, accuracy: 0.000_001)
    }
}
