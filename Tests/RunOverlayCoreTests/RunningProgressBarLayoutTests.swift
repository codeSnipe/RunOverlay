import CoreGraphics
import XCTest
@testable import RunOverlayCore

final class RunningProgressBarLayoutTests: XCTestCase {
    func test填充宽度随进度增加且不会超出轨道() {
        let bounds = CGRect(x: 20, y: 30, width: 300, height: 60)
        let start = RunningProgressBarLayout(in: bounds, progress: 0)
        let middle = RunningProgressBarLayout(in: bounds, progress: 0.5)
        let finish = RunningProgressBarLayout(in: bounds, progress: 1)

        XCTAssertEqual(start.track, middle.track)
        XCTAssertEqual(middle.track, finish.track)
        XCTAssertEqual(start.fill.width, 0)
        XCTAssertGreaterThan(middle.fill.width, start.fill.width)
        XCTAssertEqual(finish.fill.width, finish.track.width)
        XCTAssertEqual(middle.fill.minX, middle.track.minX)
        XCTAssertEqual(middle.fill.midY, middle.track.midY)
        XCTAssertGreaterThan(middle.labels.minY, middle.track.maxY)
        XCTAssertLessThan(middle.currentLabel.maxY, middle.track.minY)
        XCTAssertEqual(
            start.currentLabelCenterX(forTextWidth: 40),
            start.currentLabel.minX + 20
        )
        XCTAssertEqual(
            middle.currentLabelCenterX(forTextWidth: 40),
            middle.track.midX
        )
        XCTAssertEqual(
            finish.currentLabelCenterX(forTextWidth: 40),
            finish.currentLabel.maxX - 20
        )
        let exported = RunningProgressBarLayout(
            in: bounds,
            progress: 0.5,
            originAtTop: false
        )
        XCTAssertLessThan(exported.labels.maxY, exported.track.minY)
        XCTAssertGreaterThan(exported.currentLabel.minY, exported.track.maxY)
        XCTAssertEqual(exported.track.width, middle.track.width)
        XCTAssertEqual(exported.fill.width, middle.fill.width)
        XCTAssertEqual(
            exported.currentLabelCenterX(forTextWidth: 40),
            middle.currentLabelCenterX(forTextWidth: 40)
        )
    }

    func test无效和越界进度安全限制到零到一() {
        let bounds = CGRect(x: 0, y: 0, width: 80, height: 12)
        let invalidProgresses: [Double?] = [
            nil, .some(.nan), .some(.infinity), .some(-1)
        ]
        for progress in invalidProgresses {
            XCTAssertEqual(
                RunningProgressBarLayout(in: bounds, progress: progress).fill.width,
                0
            )
        }
        XCTAssertEqual(
            RunningProgressBarLayout(in: bounds, progress: 2).fill.width,
            RunningProgressBarLayout(in: bounds, progress: 1).track.width
        )
        XCTAssertEqual(
            RunningProgressBarLayout(
                in: CGRect(x: 0, y: 0, width: 1, height: 1),
                progress: 1
            ).fill.width,
            0
        )
    }

    func test狭窄进度条当前里程始终留在区域内() {
        let bounds = CGRect(x: 0, y: 0, width: 80, height: 12)
        for progress in [0.0, 0.05, 0.5, 0.95, 1.0] {
            let layout = RunningProgressBarLayout(in: bounds, progress: progress)
            let center = layout.currentLabelCenterX(forTextWidth: 60)
            XCTAssertGreaterThanOrEqual(center - 30, layout.currentLabel.minX)
            XCTAssertLessThanOrEqual(center + 30, layout.currentLabel.maxX)
        }
    }
}
