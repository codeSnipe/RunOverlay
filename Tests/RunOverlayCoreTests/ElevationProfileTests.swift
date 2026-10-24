import CoreGraphics
import CoreImage
import XCTest
@testable import RunOverlayCore

final class ElevationProfileTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    func test距离决定横轴海拔决定纵轴且当前位置随运动推进() throws {
        let samples = [
            makeSample(at: 0, distance: 100, altitude: 100, ascent: 0),
            makeSample(at: 10, distance: 200, altitude: 155, ascent: 55),
            makeSample(at: 20, distance: 400, altitude: 110, ascent: 55),
            makeSample(at: 30, distance: 700, altitude: 180, ascent: 125)
        ]
        let profile = ElevationProfile(samples: samples)
        XCTAssertTrue(profile.isAvailable)
        XCTAssertEqual(profile.totalDistanceMeters, 600)
        XCTAssertEqual(profile.points.first?.distanceFraction, 0)
        XCTAssertEqual(profile.points.last?.distanceFraction, 1)
        XCTAssertEqual(profile.distanceLabels.start, "0 km")
        XCTAssertEqual(profile.distanceLabels.end, "0.6 km")

        let canvas = CGRect(x: 10, y: 20, width: 280, height: 120)
        let first = try XCTUnwrap(profile.marker(
            for: samples[0], in: canvas, originAtTop: true
        ))
        let climbed = try XCTUnwrap(profile.marker(
            for: samples[1], in: canvas, originAtTop: true
        ))
        let descended = try XCTUnwrap(profile.marker(
            for: samples[2], in: canvas, originAtTop: true
        ))
        XCTAssertEqual(first.x, canvas.minX, accuracy: 0.01)
        XCTAssertEqual(descended.x, canvas.minX + canvas.width * 0.5, accuracy: 0.01)
        XCTAssertLessThan(climbed.y, descended.y)
        let export = try XCTUnwrap(profile.marker(
            for: samples[1], in: canvas, originAtTop: false
        ))
        XCTAssertEqual(export.x, climbed.x, accuracy: 0.01)
        XCTAssertEqual(export.y + climbed.y, canvas.minY + canvas.maxY, accuracy: 0.01)
        XCTAssertNil(profile.marker(
            for: makeSample(at: 35, distance: 1_000, altitude: 190, ascent: 125),
            in: canvas,
            originAtTop: true
        ))
    }

    func test缺海拔时不凭空绘制且断点不相连() {
        let missing = [
            ActivitySample(timestamp: origin, distanceMeters: 0),
            ActivitySample(timestamp: origin.addingTimeInterval(10), distanceMeters: 100)
        ]
        XCTAssertFalse(ElevationProfile(samples: missing).isAvailable)
        XCTAssertEqual(ElevationProfile(samples: missing).distanceLabels.end, "— km")
        let samples = [
            makeSample(at: 0, distance: 0, altitude: 20, ascent: 0),
            makeSample(at: 10, distance: 50, altitude: 50, ascent: 30),
            makeSample(at: 300, distance: 100, altitude: 80, ascent: 30),
            makeSample(at: 310, distance: 150, altitude: 90, ascent: 40)
        ]
        let profile = ElevationProfile(samples: samples)
        XCTAssertTrue(profile.isAvailable)
        XCTAssertTrue(profile.points[2].startsNewSegment)
        XCTAssertFalse(profile.points[1].startsNewSegment)
    }

    func test新卡片默认提供轻薄底色且可独立切换英尺单位() throws {
        var configuration = OverlayConfiguration.preset(.runningFocus)
        let chart = configuration.newElement(for: .elevationProfile)
        XCTAssertEqual(chart.backgroundOpacity, 0.32)
        XCTAssertEqual(chart.frame.width, 0.30)
        XCTAssertEqual(chart.frame.height, 0.18)
        XCTAssertTrue(OverlayElementKind.elevationProfile.supportedMeasurementUnits
            .contains(.feet))
        XCTAssertFalse(configuration.elements.contains {
            $0.kind == .elevationProfile
        })
        var feetChart = chart
        feetChart.measurementUnit = .feet
        configuration.elements.append(feetChart)
        let project = RunOverlayProject(overlay: configuration)
        let restored = try ProjectFileCodec().decode(
            ProjectFileCodec().encode(project)
        )
        XCTAssertEqual(
            restored.overlay.elements.last?.measurementUnit,
            .feet
        )
        let draft = OverlayDraft(name: "爬升曲线", configuration: configuration)
        let shared = try OverlayDraftTransferService().decode(
            OverlayDraftTransferService().encode(draft)
        )
        XCTAssertEqual(shared.configuration.elements.last, feetChart)
    }

    func test真实FIT具有完整的沿程爬升曲线() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("demo/480745612738855213.fit")
        guard FileManager.default.isReadableFile(atPath: source.path) else {
            throw XCTSkip("当前工作区没有演示 FIT 文件")
        }
        let activity = try ActivityParser().parse(from: source)
        let profile = ElevationProfile(samples: activity.samples)
        XCTAssertTrue(profile.isAvailable)
        XCTAssertGreaterThan(profile.points.count, 30)
        XCTAssertLessThan(profile.points.count, 1_000)
        XCTAssertGreaterThan(profile.maximumAltitudeMeters - profile.minimumAltitudeMeters, 100)
        XCTAssertEqual(profile.totalDistanceMeters, 6_013, accuracy: 40)
        let current = try XCTUnwrap(activity.samples.first(where: {
            $0.distanceMeters.map { $0 > 3_000 } ?? false &&
                $0.altitudeMeters != nil && $0.ascentMeters != nil
        }))
        let marker = try XCTUnwrap(profile.marker(
            for: current,
            in: CGRect(x: 0, y: 0, width: 400, height: 120),
            originAtTop: true
        ))
        XCTAssertGreaterThan(marker.x, 100)
        XCTAssertLessThan(marker.x, 400)
    }

    func test截图和导出共用数据图渲染且文字语言独立() throws {
        let samples = [
            makeSample(at: 0, distance: 0, altitude: 100, ascent: 0),
            makeSample(at: 10, distance: 200, altitude: 160, ascent: 60),
            makeSample(at: 20, distance: 400, altitude: 120, ascent: 60),
            makeSample(at: 30, distance: 600, altitude: 170, ascent: 110)
        ]
        let profile = ElevationProfile(samples: samples)
        var overlay = OverlayConfiguration.preset(.runningFocus)
        let chart = OverlayElementConfiguration(
            kind: .elevationProfile,
            frame: NormalizedRect(x: 0.2, y: 0.2, width: 0.55, height: 0.28),
            backgroundOpacity: 0,
            measurementUnit: .feet
        )
        overlay.elements = [chart]
        let size = CGSize(width: 640, height: 360)
        let renderer = OverlayFrameRenderer()
        let context = CIContext(options: [.useSoftwareRenderer: true])

        func render(sample: ActivitySample?, language: VideoTextLanguage) throws -> Data {
            let image = try XCTUnwrap(renderer.render(
                size: size,
                configuration: overlay,
                sample: sample,
                route: [],
                elevationProfile: profile,
                activityStart: origin,
                videoTextLanguage: language
            ))
            let raster = try XCTUnwrap(context.createCGImage(image, from: image.extent))
            return try XCTUnwrap(raster.dataProvider?.data as Data?)
        }
        let early = try render(sample: samples[1], language: .chinese)
        XCTAssertNotEqual(early, try render(sample: samples[3], language: .chinese))
        XCTAssertNotEqual(early, try render(sample: samples[1], language: .english))
        XCTAssertNil(renderer.render(
            size: size,
            configuration: overlay,
            sample: nil,
            route: [],
            elevationProfile: profile,
            activityStart: origin
        ))
    }

    private func makeSample(
        at offset: TimeInterval,
        distance: Double,
        altitude: Double,
        ascent: Double
    ) -> ActivitySample {
        ActivitySample(
            timestamp: origin.addingTimeInterval(offset),
            distanceMeters: distance,
            altitudeMeters: altitude,
            ascentMeters: ascent
        )
    }
}
