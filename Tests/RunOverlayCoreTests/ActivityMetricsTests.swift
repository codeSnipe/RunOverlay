import Foundation
import XCTest
@testable import RunOverlayCore

final class ActivityMetricsTests: XCTestCase {
    func testFIT分圈汇总生成动态累计数据() throws {
        let start: UInt32 = 1_160_000_000
        var payload: [UInt8] = []

        // record 时间戳和高程；高程是 FIT 标准的五倍偏移编码。
        payload += definition(local: 0, global: 20, fields: [
            (253, 4, 0x86), (2, 2, 0x84)
        ])
        for offset in [0, 10, 20] {
            payload += [0x00]
            payload += littleEndian(start + UInt32(offset))
            payload += littleEndian(UInt16(3_000 + offset * 5))
        }
        payload += definition(local: 1, global: 19, fields: [
            (253, 4, 0x86), (21, 2, 0x84), (11, 2, 0x84)
        ])
        payload += [0x01]
        payload += littleEndian(start + 20)
        payload += littleEndian(UInt16(12))
        payload += littleEndian(UInt16(100))

        for offset in [30, 40] {
            payload += [0x00]
            payload += littleEndian(start + UInt32(offset))
            payload += littleEndian(UInt16(3_000 + offset * 5))
        }
        payload += [0x01]
        payload += littleEndian(start + 40)
        payload += littleEndian(UInt16(10))
        payload += littleEndian(UInt16(80))
        payload += definition(local: 2, global: 18, fields: [
            (253, 4, 0x86), (22, 2, 0x84), (11, 2, 0x84)
        ])
        payload += [0x02]
        payload += littleEndian(start + 40)
        payload += littleEndian(UInt16(22))
        payload += littleEndian(UInt16(180))

        let url = try temporaryFile(extension: "fit", data: fitFile(payload))
        let activity = try ActivityParser().parse(from: url)

        XCTAssertEqual(activity.samples.count, 5)
        XCTAssertEqual(activity.samples.map(\.ascentMeters), [0, 6, 12, 17, 22])
        XCTAssertEqual(activity.samples.map(\.caloriesKilocalories), [0, 50, 100, 140, 180])
        XCTAssertTrue(activity.availableChannels.contains(.ascent))
        XCTAssertTrue(activity.availableChannels.contains(.calories))
    }

    func testFIT记录卡路里和高程推导爬升() throws {
        let start: UInt32 = 1_160_000_000
        var payload: [UInt8] = []
        payload += definition(local: 0, global: 20, fields: [
            (253, 4, 0x86), (2, 2, 0x84), (33, 2, 0x84)
        ])
        for (offset, altitude, calories): (Int, UInt16, UInt16) in [
            (0, 3_000, 0),
            (10, 3_025, 12),
            (20, 3_050, 24)
        ] {
            payload += [0x00]
            payload += littleEndian(start + UInt32(offset))
            payload += littleEndian(altitude)
            payload += littleEndian(calories)
        }
        let activity = try ActivityParser().parse(
            from: temporaryFile(extension: "fit", data: fitFile(payload))
        )

        XCTAssertEqual(activity.samples.map(\.ascentMeters), [0, 5, 10])
        XCTAssertEqual(activity.samples.map(\.caloriesKilocalories), [0, 12, 24])
    }

    func testGPX扩展卡路里和高程过滤尖峰() throws {
        let altitudes = [100.0, 150, 101, 104, 107]
        let points = altitudes.enumerated().map { index, altitude in
            """
            <trkpt lat="31" lon="121">
              <ele>\(altitude)</ele><time>2026-09-23T06:00:\(String(format: "%02d", index * 10))Z</time>
              <extensions><run:calories>\(index * 10)</run:calories></extensions>
            </trkpt>
            """
        }.joined()
        let gpx = """
        <gpx xmlns:run="https://example.com/run"><trk><trkseg>\(points)</trkseg></trk></gpx>
        """
        let activity = try ActivityParser().parse(
            from: temporaryFile(extension: "gpx", data: Data(gpx.utf8))
        )

        XCTAssertEqual(activity.samples.map(\.caloriesKilocalories), [0, 10, 20, 30, 40])
        XCTAssertEqual(activity.samples.last?.ascentMeters, 7)
        XCTAssertEqual(activity.samples[1].ascentMeters, 0)
    }

    func test无卡路里时保持缺失且旧JSON可读() throws {
        let sample = ActivitySample(timestamp: Date(timeIntervalSince1970: 100))
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? [String: Any]
        )
        json.removeValue(forKey: "ascentMeters")
        json.removeValue(forKey: "caloriesKilocalories")
        let restored = try JSONDecoder().decode(
            ActivitySample.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertNil(restored.ascentMeters)
        XCTAssertNil(restored.caloriesKilocalories)

        let activity = try ActivityNormalizer().normalize([restored], kind: .gpx)
        XCTAssertFalse(activity.availableChannels.contains(.ascent))
        XCTAssertFalse(activity.availableChannels.contains(.calories))
    }

    private func definition(
        local: UInt8,
        global: UInt16,
        fields: [(UInt8, UInt8, UInt8)]
    ) -> [UInt8] {
        var bytes: [UInt8] = [0x40 | local, 0, 0]
        bytes += littleEndian(global)
        bytes += [UInt8(fields.count)]
        for (number, size, type) in fields {
            bytes += [number, size, type]
        }
        return bytes
    }

    private func fitFile(_ payload: [UInt8]) -> Data {
        var bytes: [UInt8] = [12, 0x20, 0, 0]
        bytes += littleEndian(UInt32(payload.count))
        bytes += Array(".FIT".utf8)
        return Data(bytes + payload)
    }

    private func littleEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    private func temporaryFile(extension fileExtension: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("运动.\(fileExtension)")
        try data.write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return url
    }
}
