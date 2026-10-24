import Foundation
import XCTest
@testable import RunOverlayCore

final class ActivityProgressCalculatorTests: XCTestCase {
    func test优先按累计距离计算且支持非零起始里程() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            ActivitySample(timestamp: start, distanceMeters: 100),
            ActivitySample(
                timestamp: start.addingTimeInterval(10),
                distanceMeters: 600
            ),
            ActivitySample(
                timestamp: start.addingTimeInterval(20),
                distanceMeters: 1_100
            )
        ]
        let current = ActivitySample(
            timestamp: start.addingTimeInterval(2),
            distanceMeters: 300
        )

        XCTAssertEqual(
            try XCTUnwrap(
                ActivityProgressCalculator(samples: samples).fraction(for: current)
            ),
            0.2,
            accuracy: 0.000_001
        )
        let progress = try XCTUnwrap(
            ActivityProgressCalculator(samples: samples).progress(for: current)
        )
        XCTAssertEqual(progress.startLabel, "0km")
        XCTAssertEqual(progress.currentLabel, "0.20 km")
        XCTAssertEqual(progress.totalLabel, "1.00 km")
    }

    func test距离回退不会让进度倒退() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            ActivitySample(timestamp: start, distanceMeters: 100),
            ActivitySample(
                timestamp: start.addingTimeInterval(10),
                distanceMeters: 600
            ),
            ActivitySample(
                timestamp: start.addingTimeInterval(20),
                distanceMeters: 400
            ),
            ActivitySample(
                timestamp: start.addingTimeInterval(30),
                distanceMeters: 1_100
            )
        ]
        let calculator = ActivityProgressCalculator(samples: samples)
        let beforeRegression = ActivitySample(
            timestamp: start.addingTimeInterval(10),
            distanceMeters: 600
        )
        let afterRegression = ActivitySample(
            timestamp: start.addingTimeInterval(20),
            distanceMeters: 400
        )

        XCTAssertEqual(
            try XCTUnwrap(calculator.fraction(for: beforeRegression)),
            try XCTUnwrap(calculator.fraction(for: afterRegression)),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            calculator.progress(for: afterRegression)?.currentLabel,
            "0.50 km"
        )
    }

    func test距离不可用时按运动时间推进并限制边界() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            ActivitySample(timestamp: start, distanceMeters: 10),
            ActivitySample(
                timestamp: start.addingTimeInterval(20),
                distanceMeters: 10
            )
        ]
        let calculator = ActivityProgressCalculator(samples: samples)

        XCTAssertEqual(
            try XCTUnwrap(calculator.fraction(for: ActivitySample(
                timestamp: start.addingTimeInterval(10)
            ))),
            0.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(calculator.fraction(for: ActivitySample(
                timestamp: start.addingTimeInterval(-10)
            ))),
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(calculator.fraction(for: ActivitySample(
                timestamp: start.addingTimeInterval(30)
            ))),
            1,
            accuracy: 0.000_001
        )
    }

    func test空数据和单点数据安全返回() {
        let sample = ActivitySample(
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertNil(ActivityProgressCalculator().fraction(for: nil))
        XCTAssertEqual(
            ActivityProgressCalculator().fraction(for: sample),
            0
        )
        XCTAssertEqual(
            ActivityProgressCalculator(samples: [sample]).fraction(for: sample),
            0
        )
    }

    func test缺少距离时三处公里数不显示虚构值() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let calculator = ActivityProgressCalculator(samples: [
            ActivitySample(timestamp: start),
            ActivitySample(timestamp: start.addingTimeInterval(20))
        ])
        let progress = try XCTUnwrap(calculator.progress(
            for: ActivitySample(timestamp: start.addingTimeInterval(10))
        ))

        XCTAssertEqual(progress.fraction, 0.5)
        XCTAssertEqual(progress.startLabel, "0km")
        XCTAssertEqual(progress.currentLabel, "— km")
        XCTAssertEqual(progress.totalLabel, "— km")
    }
}
