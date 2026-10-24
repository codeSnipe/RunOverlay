import CoreGraphics
import XCTest
@testable import RunOverlayCore

final class OverlayHitTesterTests: XCTestCase {
    private let canvasSize = CGSize(width: 1_000, height: 600)

    func test点击卡片内部直接选中未选图层() throws {
        let element = OverlayElementConfiguration(
            kind: .pace,
            frame: NormalizedRect(x: 0.1, y: 0.7, width: 0.2, height: 0.2)
        )

        let target = try XCTUnwrap(
            OverlayHitTester.target(
                at: CGPoint(x: 200, y: 480),
                in: canvasSize,
                elements: [element],
                selectedElementID: nil
            )
        )

        XCTAssertEqual(target.elementID, element.id)
        XCTAssertNil(target.handle)
    }

    func test选中图层后整圈边框可缩放而中心仍可移动() {
        let element = OverlayElementConfiguration(
            kind: .pace,
            frame: NormalizedRect(x: 0.1, y: 0.7, width: 0.2, height: 0.2)
        )
        let samples: [(CGPoint, OverlayResizeHandle?)] = [
            (CGPoint(x: 114, y: 434), .topLeading),
            (CGPoint(x: 200, y: 434), .top),
            (CGPoint(x: 286, y: 434), .topTrailing),
            (CGPoint(x: 286, y: 480), .trailing),
            (CGPoint(x: 114, y: 526), .bottomLeading),
            (CGPoint(x: 200, y: 526), .bottom),
            (CGPoint(x: 286, y: 526), .bottomTrailing),
            (CGPoint(x: 114, y: 480), .leading),
            (CGPoint(x: 200, y: 480), nil)
        ]

        for (point, expectedHandle) in samples {
            let target = OverlayHitTester.target(
                at: point,
                in: canvasSize,
                elements: [element],
                selectedElementID: element.id
            )
            XCTAssertEqual(target?.elementID, element.id)
            XCTAssertEqual(target?.handle, expectedHandle)
        }
    }

    func test边框外侧少许也可抓取但未选中时只会选中() {
        let element = OverlayElementConfiguration(
            kind: .pace,
            frame: NormalizedRect(x: 0.1, y: 0.7, width: 0.2, height: 0.2)
        )
        let point = CGPoint(x: 200, y: 416)
        XCTAssertEqual(
            OverlayHitTester.target(
                at: point,
                in: canvasSize,
                elements: [element],
                selectedElementID: element.id
            )?.handle,
            .top
        )
        XCTAssertNil(
            OverlayHitTester.target(
                at: point,
                in: canvasSize,
                elements: [element],
                selectedElementID: nil
            )
        )
    }

    func test空白区域与隐藏图层不拦截点击() {
        var element = OverlayElementConfiguration(
            kind: .pace,
            frame: NormalizedRect(x: 0.1, y: 0.7, width: 0.2, height: 0.2)
        )
        XCTAssertNil(
            OverlayHitTester.target(
                at: CGPoint(x: 500, y: 100),
                in: canvasSize,
                elements: [element],
                selectedElementID: nil
            )
        )
        element.isVisible = false
        XCTAssertNil(
            OverlayHitTester.target(
                at: CGPoint(x: 200, y: 480),
                in: canvasSize,
                elements: [element],
                selectedElementID: nil
            )
        )
    }

    func test竖屏窄卡片命中范围不会比实际图层更宽() {
        let element = OverlayElementConfiguration(
            kind: .calories,
            frame: NormalizedRect(x: 0.04, y: 0.54, width: 0.19, height: 0.10)
        )
        let portrait = CGSize(width: 180, height: 320)

        XCTAssertNotNil(
            OverlayHitTester.target(
                at: CGPoint(x: 35, y: 190),
                in: portrait,
                elements: [element],
                selectedElementID: nil
            )
        )
        XCTAssertNil(
            OverlayHitTester.target(
                at: CGPoint(x: 48, y: 190),
                in: portrait,
                elements: [element],
                selectedElementID: nil
            )
        )
    }
}
