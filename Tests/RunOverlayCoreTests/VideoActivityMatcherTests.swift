import XCTest
@testable import RunOverlayCore

final class VideoActivityMatcherTests: XCTestCase {
    private let matcher = VideoActivityMatcher()
    private let activityStart = Date(timeIntervalSince1970: 1_700_000_000)

    func test完整覆盖时返回已匹配() {
        let activityRange = DateInterval(
            start: activityStart,
            duration: 3_600
        )
        let result = matcher.match(
            videoStart: activityStart.addingTimeInterval(300),
            duration: 60,
            activityRange: activityRange
        )

        XCTAssertEqual(result.status, .complete)
        XCTAssertEqual(result.matchedRange?.duration, 60)
    }

    func test只有部分时间重叠时返回部分匹配() {
        let activityRange = DateInterval(
            start: activityStart,
            duration: 600
        )
        let result = matcher.match(
            videoStart: activityStart.addingTimeInterval(570),
            duration: 60,
            activityRange: activityRange
        )

        XCTAssertEqual(result.status, .partial)
        XCTAssertEqual(result.matchedRange?.duration, 30)
    }

    func test没有拍摄时间时返回未匹配() {
        let result = matcher.match(
            videoStart: nil,
            duration: 60,
            activityRange: DateInterval(start: activityStart, duration: 600)
        )

        XCTAssertEqual(result.status, .unmatched)
        XCTAssertNil(result.matchedRange)
    }

    func test时间偏移参与匹配() {
        let activityRange = DateInterval(
            start: activityStart,
            duration: 600
        )
        let result = matcher.match(
            videoStart: activityStart.addingTimeInterval(-60),
            duration: 30,
            activityRange: activityRange,
            timeOffset: 60,
            calibrationMethod: .timeOffset
        )

        XCTAssertEqual(result.status, .complete)
        XCTAssertEqual(result.timeOffset, 60)
        XCTAssertEqual(result.calibrationMethod, .timeOffset)
    }
}
