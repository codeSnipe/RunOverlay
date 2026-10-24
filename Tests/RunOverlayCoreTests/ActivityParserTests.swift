import Foundation
import XCTest
@testable import RunOverlayCore

final class ActivityParserTests: XCTestCase {
    func test解析GPX轨迹和扩展运动字段() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
          <trk><trkseg>
            <trkpt lat="31.2304" lon="121.4737">
              <ele>12.5</ele>
              <time>2026-09-23T06:00:00Z</time>
              <extensions>
                <gpxtpx:TrackPointExtension>
                  <gpxtpx:hr>151</gpxtpx:hr>
                  <gpxtpx:cad>176</gpxtpx:cad>
                </gpxtpx:TrackPointExtension>
                <power>288</power>
              </extensions>
            </trkpt>
            <trkpt lat="31.2305" lon="121.4738">
              <ele>13.1</ele>
              <time>2026-09-23T06:00:05.000Z</time>
              <extensions>
                <gpxtpx:TrackPointExtension>
                  <gpxtpx:hr>153</gpxtpx:hr>
                  <gpxtpx:cad>178</gpxtpx:cad>
                </gpxtpx:TrackPointExtension>
              </extensions>
            </trkpt>
          </trkseg></trk>
        </gpx>
        """
        let url = try temporaryFile(
            name: "活动.gpx",
            data: Data(gpx.utf8)
        )

        let result = try ActivityParser().parse(from: url)

        XCTAssertEqual(result.kind, .gpx)
        XCTAssertEqual(result.samples.count, 2)
        XCTAssertEqual(result.samples[0].heartRate, 151)
        XCTAssertEqual(result.samples[0].cadence, 176)
        XCTAssertEqual(result.samples[0].power, 288)
        XCTAssertEqual(result.samples[0].altitudeMeters, 12.5)
        XCTAssertNotNil(result.samples[1].distanceMeters)
        XCTAssertNotNil(result.samples[1].speedMetersPerSecond)
        XCTAssertTrue(result.availableChannels.contains(.location))
        XCTAssertTrue(result.availableChannels.contains(.heartRate))
    }

    func test解析FIT记录消息() throws {
        let timestamp: UInt32 = 1_160_000_000
        var payload: [UInt8] = []

        // 本地消息 0 的定义：全局消息 20（record），小端序。
        payload += [0x40, 0x00, 0x00]
        payload += littleEndian(UInt16(20))
        payload += [0x08]
        payload += [253, 4, 0x86]
        payload += [0, 4, 0x85]
        payload += [1, 4, 0x85]
        payload += [5, 4, 0x86]
        payload += [6, 2, 0x84]
        payload += [3, 1, 0x02]
        payload += [4, 1, 0x02]
        payload += [7, 2, 0x84]

        payload += [0x00]
        payload += littleEndian(timestamp)
        payload += littleEndian(Int32(372_589_318))
        payload += littleEndian(Int32(1_449_318_075))
        payload += littleEndian(UInt32(123_456))
        payload += littleEndian(UInt16(3_200))
        payload += [152]
        payload += [177]
        payload += littleEndian(UInt16(275))

        var bytes: [UInt8] = [
            12,
            0x20,
            0x00, 0x00
        ]
        bytes += littleEndian(UInt32(payload.count))
        bytes += Array(".FIT".utf8)
        bytes += payload

        let url = try temporaryFile(
            name: "活动.fit",
            data: Data(bytes)
        )
        let result = try ActivityParser().parse(from: url)

        XCTAssertEqual(result.kind, .fit)
        XCTAssertEqual(result.samples.count, 1)
        XCTAssertEqual(
            try XCTUnwrap(result.samples[0].distanceMeters),
            1_234.56,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(result.samples[0].speedMetersPerSecond),
            3.2,
            accuracy: 0.001
        )
        XCTAssertEqual(result.samples[0].heartRate, 152)
        XCTAssertEqual(result.samples[0].cadence, 177)
        XCTAssertEqual(result.samples[0].power, 275)
        XCTAssertTrue(result.availableChannels.contains(.location))
    }

    func test时间轴插值并拒绝跨越大间隔() throws {
        let start = Date(timeIntervalSince1970: 100)
        let samples = [
            ActivitySample(
                timestamp: start,
                distanceMeters: 10,
                speedMetersPerSecond: 2
            ),
            ActivitySample(
                timestamp: start.addingTimeInterval(10),
                distanceMeters: 40,
                speedMetersPerSecond: 4
            )
        ]
        let timeline = ActivityTimeline()

        let middle = timeline.sample(
            at: start.addingTimeInterval(5),
            in: samples
        )
        XCTAssertEqual(middle?.distanceMeters, 25)
        XCTAssertEqual(middle?.speedMetersPerSecond, 3)

        let missing = timeline.sample(
            at: start.addingTimeInterval(5),
            in: samples,
            maximumGap: 4
        )
        XCTAssertNil(missing)
    }

    func test时间轴插值累计爬升与卡路里() {
        let start = Date(timeIntervalSince1970: 100)
        let samples = [
            ActivitySample(
                timestamp: start,
                ascentMeters: 10,
                caloriesKilocalories: 40
            ),
            ActivitySample(
                timestamp: start.addingTimeInterval(10),
                ascentMeters: 30,
                caloriesKilocalories: 60
            )
        ]

        let middle = ActivityTimeline().sample(
            at: start.addingTimeInterval(5),
            in: samples
        )

        XCTAssertEqual(middle?.ascentMeters, 20)
        XCTAssertEqual(middle?.caloriesKilocalories, 50)
    }

    private func temporaryFile(name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return url
    }

    private func littleEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }
}
