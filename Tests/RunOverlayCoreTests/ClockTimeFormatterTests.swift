import Foundation
import XCTest
@testable import RunOverlayCore

final class ClockTimeFormatterTests: XCTestCase {
    func test时钟采用本地时区并精确到秒() {
        let timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let timestamp = Date(timeIntervalSince1970: 0)

        XCTAssertEqual(
            RunOverlayFormatters.clockTime(timestamp, timeZone: timeZone),
            "08:00:00"
        )
        XCTAssertEqual(
            RunOverlayFormatters.clockDateTime(timestamp, timeZone: timeZone),
            "1970-01-01 08:00:00"
        )
        XCTAssertEqual(
            RunOverlayFormatters.clockTime(
                timestamp.addingTimeInterval(61),
                timeZone: timeZone
            ),
            "08:01:01"
        )
        XCTAssertEqual(
            RunOverlayFormatters.clockTime(nil, timeZone: timeZone),
            "—:—:—"
        )
        XCTAssertEqual(
            RunOverlayFormatters.clockDateTime(nil, timeZone: timeZone),
            "—-—-— —:—:—"
        )
    }

    func test日期与时钟共用时区并可跨日() {
        let timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let timestamp = Date(timeIntervalSince1970: -9 * 3_600)

        XCTAssertEqual(
            RunOverlayFormatters.clockDate(timestamp, timeZone: timeZone),
            "1969-12-31"
        )
        XCTAssertEqual(
            RunOverlayFormatters.clockTime(timestamp, timeZone: timeZone),
            "23:00:00"
        )
        XCTAssertEqual(
            RunOverlayFormatters.clockDateTime(timestamp, timeZone: timeZone),
            "1969-12-31 23:00:00"
        )
        XCTAssertEqual(
            RunOverlayFormatters.clockDate(
                timestamp.addingTimeInterval(3_600),
                timeZone: timeZone
            ),
            "1970-01-01"
        )
        XCTAssertEqual(
            RunOverlayFormatters.clockDate(nil, timeZone: timeZone),
            "—-—-—"
        )
    }

    func test日期和运动时长的独立显示格式() {
        let timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let timestamp = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(
            RunOverlayFormatters.clock(timestamp, display: .date, timeZone: timeZone),
            "1970-01-01"
        )
        XCTAssertEqual(
            RunOverlayFormatters.clock(timestamp, display: .time, timeZone: timeZone),
            "08:00:00"
        )
        let sample = ActivitySample(
            timestamp: timestamp.addingTimeInterval(22 * 60 + 34)
        )
        XCTAssertEqual(
            RunOverlayFormatters.activityDuration(
                sample: sample,
                start: timestamp,
                display: .hoursMinutesSeconds
            ),
            "00:22:34"
        )
        XCTAssertEqual(
            RunOverlayFormatters.activityDuration(
                sample: sample,
                start: timestamp,
                display: .adaptive
            ),
            "22:34"
        )
    }
}
