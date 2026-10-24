import CoreImage
import XCTest
@testable import RunOverlayCore

final class OverlayFrameRendererTests: XCTestCase {
    func test跑步聚焦右下角日期时间单行渲染且随秒更新() throws {
        var configuration = OverlayConfiguration.preset(.runningFocus)
        configuration.elements = configuration.elements.filter { $0.kind == .clockTime }
        let clock = try XCTUnwrap(configuration.elements.first)
        XCTAssertEqual(clock.clockDisplay, .dateTime)

        let size = CGSize(width: 960, height: 540)
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let renderer = OverlayFrameRenderer()
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let rect = CGRect(
            x: clock.frame.x * size.width,
            y: (1 - clock.frame.y - clock.frame.height) * size.height,
            width: clock.frame.width * size.width,
            height: clock.frame.height * size.height
        )
        let centerY = Int(size.height - rect.midY)

        func renderedPixels(at date: Date) throws -> Data {
            let image = try XCTUnwrap(renderer.render(
                size: size,
                configuration: configuration,
                sample: nil,
                route: [],
                activityStart: nil,
                clockTime: date
            ))
            let cgImage = try XCTUnwrap(context.createCGImage(image, from: image.extent))
            return try XCTUnwrap(cgImage.dataProvider?.data as Data?)
        }

        let first = try renderedPixels(at: timestamp)
        XCTAssertNotEqual(first, try renderedPixels(at: timestamp.addingTimeInterval(1)))
        func visibleCount(in rows: ClosedRange<Int>) -> Int {
            var count = 0
            for y in rows {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    if first[(y * Int(size.width) + x) * 4 + 3] > 80 {
                        count += 1
                    }
                }
            }
            return count
        }
        XCTAssertGreaterThan(
            visibleCount(in: (centerY - 12)...(centerY + 12)),
            20
        )
        XCTAssertEqual(
            visibleCount(in: (centerY + 20)...(centerY + 30)),
            0,
            "时钟图层不应出现第二行"
        )
    }

    func test跑步聚焦轨迹当前位置随采样移动且导出方向正确() throws {
        let route = [
            GeoCoordinate(latitude: 30.00, longitude: 120.00),
            GeoCoordinate(latitude: 30.005, longitude: 120.01),
            GeoCoordinate(latitude: 30.02, longitude: 120.02)
        ]
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let size = CGSize(width: 400, height: 400)
        let frame = NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        var configuration = OverlayConfiguration.preset(.runningFocus)
        configuration.elements = [
            OverlayElementConfiguration(
                kind: .route, frame: frame, backgroundOpacity: 0
            )
        ]
        let renderer = OverlayFrameRenderer()
        let imageContext = CIContext(options: [.useSoftwareRenderer: true])
        let card = CGRect(
            x: frame.x * size.width,
            y: (1 - frame.y - frame.height) * size.height,
            width: frame.width * size.width,
            height: frame.height * size.height
        )
        let routeRect = card.insetBy(dx: card.width * 0.08, dy: card.height * 0.08)
        let south = try XCTUnwrap(
            RouteProjection.coreGraphicsPoints(for: [route[0]], in: routeRect, using: route).first
        )
        let north = try XCTUnwrap(
            RouteProjection.coreGraphicsPoints(for: [route[2]], in: routeRect, using: route).first
        )

        func brightPixels(around point: CGPoint, current: GeoCoordinate) throws -> Int {
            let image = try XCTUnwrap(renderer.render(
                size: size,
                configuration: configuration,
                sample: ActivitySample(timestamp: timestamp, coordinate: current),
                route: route,
                activityStart: nil
            ))
            let cgImage = try XCTUnwrap(imageContext.createCGImage(image, from: image.extent))
            let pixels = try XCTUnwrap(cgImage.dataProvider?.data as Data?)
            let x = Int(point.x)
            let y = Int(size.height - point.y)
            var count = 0
            for row in max(0, y - 8)...min(cgImage.height - 1, y + 8) {
                for column in max(0, x - 8)...min(cgImage.width - 1, x + 8) {
                    let offset = (row * cgImage.width + column) * 4
                    if pixels[offset + 3] > 140 &&
                       pixels[offset] > 220 &&
                       pixels[offset + 1] > 220 &&
                       pixels[offset + 2] > 220 {
                        count += 1
                    }
                }
            }
            return count
        }

        XCTAssertGreaterThan(north.y, south.y)
        XCTAssertGreaterThan(
            try brightPixels(around: south, current: route[0]),
            try brightPixels(around: south, current: route[2]) + 10
        )
        XCTAssertGreaterThan(
            try brightPixels(around: north, current: route[2]),
            try brightPixels(around: north, current: route[0]) + 10
        )
    }

    func test跑步进度变化会改变导出图层() throws {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = ActivitySample(timestamp: timestamp, distanceMeters: 500)
        var configuration = OverlayConfiguration.preset(.runningFocus)
        configuration.elements = [
            OverlayElementConfiguration(
                kind: .progress,
                frame: NormalizedRect(x: 0.1, y: 0.4, width: 0.8, height: 0.2)
            )
        ]
        let renderer = OverlayFrameRenderer()
        let context = CIContext(options: [.useSoftwareRenderer: true])

        func pixels(progress: Double) throws -> Data {
            let image = try XCTUnwrap(renderer.render(
                size: CGSize(width: 320, height: 180),
                configuration: configuration,
                sample: sample,
                activityProgress: ActivityProgress(
                    fraction: progress,
                    currentDistanceMeters: progress * 10_000,
                    totalDistanceMeters: 10_000
                ),
                route: [],
                activityStart: timestamp
            ))
            let cgImage = try XCTUnwrap(
                context.createCGImage(image, from: image.extent)
            )
            return try XCTUnwrap(cgImage.dataProvider?.data as Data?)
        }

        XCTAssertNotEqual(
            try pixels(progress: 0.25),
            try pixels(progress: 0.75)
        )
    }

    func test横竖屏进度条下方当前里程会随采样更新() throws {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = ActivitySample(timestamp: timestamp, distanceMeters: 2_000)
        var configuration = OverlayConfiguration.preset(.runningFocus)
        configuration.elements = [
            OverlayElementConfiguration(
                kind: .progress,
                frame: NormalizedRect(x: 0.05, y: 0.4, width: 0.9, height: 0.12)
            )
        ]
        let renderer = OverlayFrameRenderer()
        let context = CIContext(options: [.useSoftwareRenderer: true])

        for size in [
            CGSize(width: 320, height: 180),
            CGSize(width: 180, height: 320)
        ] {
            func pixels(currentDistance: Double) throws -> Data {
                let image = try XCTUnwrap(renderer.render(
                    size: size,
                    configuration: configuration,
                    sample: sample,
                    activityProgress: ActivityProgress(
                        fraction: 0.5,
                        currentDistanceMeters: currentDistance,
                        totalDistanceMeters: 4_000
                    ),
                    route: [],
                    activityStart: timestamp
                ))
                let cgImage = try XCTUnwrap(
                    context.createCGImage(image, from: image.extent)
                )
                return try XCTUnwrap(cgImage.dataProvider?.data as Data?)
            }

            XCTAssertNotEqual(
                try pixels(currentDistance: 1_000),
                try pixels(currentDistance: 2_000),
                "\(Int(size.width))×\(Int(size.height)) 的当前里程应绘制在进度条下方"
            )
        }
    }

    func test无运动采样时仍能绘制独立时钟图层() throws {
        var configuration = OverlayConfiguration.preset(.sport)
        configuration.elements = [OverlayConfiguration.clockTimeElement()]
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let renderer = OverlayFrameRenderer()

        let first = try XCTUnwrap(
            renderer.render(
                size: CGSize(width: 360, height: 640),
                configuration: configuration,
                sample: nil,
                route: [],
                activityStart: nil,
                clockTime: timestamp
            )
        )
        let second = try XCTUnwrap(
            renderer.render(
                size: CGSize(width: 360, height: 640),
                configuration: configuration,
                sample: nil,
                route: [],
                activityStart: nil,
                clockTime: timestamp.addingTimeInterval(1)
            )
        )
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let firstCGImage = try XCTUnwrap(
            context.createCGImage(first, from: first.extent)
        )
        let secondCGImage = try XCTUnwrap(
            context.createCGImage(second, from: second.extent)
        )

        XCTAssertEqual(first.extent.size, CGSize(width: 360, height: 640))
        XCTAssertNotEqual(
            firstCGImage.dataProvider?.data as Data?,
            secondCGImage.dataProvider?.data as Data?
        )
    }

    func test轨迹导出方向与预览一致且当前位置标记没有倒置() throws {
        let route = [
            GeoCoordinate(latitude: 30.00, longitude: 120.00),
            GeoCoordinate(latitude: 30.005, longitude: 120.01),
            GeoCoordinate(latitude: 30.02, longitude: 120.02)
        ]
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = ActivitySample(timestamp: timestamp, coordinate: route[2])
        let size = CGSize(width: 400, height: 400)
        let frame = NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        var configuration = OverlayConfiguration.preset(.sport)
        configuration.elements = [OverlayElementConfiguration(
            kind: .route, frame: frame, backgroundOpacity: 0
        )]

        let image = try XCTUnwrap(OverlayFrameRenderer().render(
            size: size,
            configuration: configuration,
            sample: sample,
            route: route,
            activityStart: nil
        ))
        let cgImage = try XCTUnwrap(
            CIContext(options: [.useSoftwareRenderer: true])
                .createCGImage(image, from: image.extent)
        )
        let alpha = try XCTUnwrap(cgImage.dataProvider?.data as Data?)
        let card = CGRect(
            x: frame.x * size.width,
            y: (1 - frame.y - frame.height) * size.height,
            width: frame.width * size.width,
            height: frame.height * size.height
        )
        let routeRect = card.insetBy(
            dx: card.width * 0.08,
            dy: card.height * 0.08
        )
        let north = try XCTUnwrap(RouteProjection.coreGraphicsPoints(
            for: [route[2]], in: routeRect, using: route
        ).first)
        let south = try XCTUnwrap(RouteProjection.coreGraphicsPoints(
            for: [route[0]], in: routeRect, using: route
        ).first)
        XCTAssertGreaterThan(north.y, south.y)

        func visiblePixels(around point: CGPoint) -> Int {
            let centerX = Int(point.x)
            let centerY = Int(size.height - point.y)
            var count = 0
            for y in max(0, centerY - 7)...min(cgImage.height - 1, centerY + 7) {
                for x in max(0, centerX - 7)...min(cgImage.width - 1, centerX + 7) {
                    let offset = (y * cgImage.width + x) * 4 + 3
                    if alpha[offset] > 80 { count += 1 }
                }
            }
            return count
        }

        XCTAssertGreaterThan(visiblePixels(around: north), 25)
        XCTAssertGreaterThan(visiblePixels(around: south), 10)
        let invertedNorth = CGPoint(x: north.x, y: size.height - north.y)
        XCTAssertEqual(visiblePixels(around: invertedNorth), 0)
    }

    func test时钟没有拍摄时间时仍显示占位卡片() {
        var configuration = OverlayConfiguration.preset(.sport)
        configuration.elements = [OverlayConfiguration.clockTimeElement()]

        let result = OverlayFrameRenderer().render(
            size: CGSize(width: 360, height: 640),
            configuration: configuration,
            sample: nil,
            route: [],
            activityStart: nil
        )

        XCTAssertNotNil(result)
    }

    func test匹配数据时生成完整尺寸的蒙层图像() throws {
        let renderer = OverlayFrameRenderer()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let sample = ActivitySample(
            timestamp: timestamp,
            coordinate: GeoCoordinate(latitude: 31.2, longitude: 121.4),
            distanceMeters: 2_345,
            speedMetersPerSecond: 3.4,
            heartRate: 151
        )

        let image = try XCTUnwrap(
            renderer.render(
                size: CGSize(width: 1_920, height: 1_080),
                configuration: .preset(.sport),
                sample: sample,
                route: [
                    GeoCoordinate(latitude: 31.2, longitude: 121.4),
                    GeoCoordinate(latitude: 31.21, longitude: 121.41)
                ],
                activityStart: timestamp.addingTimeInterval(-600)
            )
        )

        XCTAssertEqual(image.extent.width, 1_920)
        XCTAssertEqual(image.extent.height, 1_080)
    }

    func test没有匹配数据且时钟隐藏时不生成蒙层() {
        var configuration = OverlayConfiguration.preset(.sport)
        for index in configuration.elements.indices
        where configuration.elements[index].kind == .clockTime {
            configuration.elements[index].isVisible = false
        }
        let image = OverlayFrameRenderer().render(
            size: CGSize(width: 1_920, height: 1_080),
            configuration: configuration,
            sample: nil,
            route: [],
            activityStart: nil
        )

        XCTAssertNil(image)
    }

    func test背景透明度在导出中仅影响底板() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        var transparentConfiguration = OverlayConfiguration.preset(.sport)
        transparentConfiguration.elements = [OverlayElementConfiguration(
            kind: .clockTime,
            frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
            backgroundOpacity: 0
        )]
        var opaqueConfiguration = transparentConfiguration
        opaqueConfiguration.elements[0].backgroundOpacity = 1
        let renderer = OverlayFrameRenderer()

        let transparentImage = try XCTUnwrap(
            renderer.render(
                size: CGSize(width: 160, height: 120),
                configuration: transparentConfiguration,
                sample: nil,
                route: [],
                activityStart: nil,
                clockTime: timestamp
            )
        )
        let opaqueImage = try XCTUnwrap(
            renderer.render(
                size: CGSize(width: 160, height: 120),
                configuration: opaqueConfiguration,
                sample: nil,
                route: [],
                activityStart: nil,
                clockTime: timestamp
            )
        )
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let transparentCGImage = try XCTUnwrap(
            context.createCGImage(transparentImage, from: transparentImage.extent)
        )
        let opaqueCGImage = try XCTUnwrap(
            context.createCGImage(opaqueImage, from: opaqueImage.extent)
        )
        let transparentPixels = try XCTUnwrap(
            transparentCGImage.dataProvider?.data as Data?
        )
        let opaquePixels = try XCTUnwrap(opaqueCGImage.dataProvider?.data as Data?)

        let alphaValues = transparentPixels.enumerated()
            .filter { $0.offset % 4 == 3 }
            .map(\.element)

        XCTAssertTrue(alphaValues.contains(0), "文字之外应保持透明")
        XCTAssertTrue(alphaValues.contains { $0 > 0 }, "日期和时间仍应可见")
        XCTAssertNotEqual(transparentPixels, opaquePixels)
        let opaqueAlphaCount = opaquePixels.enumerated()
            .filter { $0.offset % 4 == 3 && $0.element > 0 }
            .count
        let transparentAlphaCount = alphaValues.filter { $0 > 0 }.count
        XCTAssertGreaterThan(
            opaqueAlphaCount,
            transparentAlphaCount,
            "背景透明度为 1 时，底板覆盖的像素应更多"
        )
    }

    func test独立文字大小与赛场卡片背景在导出中生效() throws {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        var configuration = OverlayConfiguration.preset(.stadiumLive)
        configuration.elements = [OverlayElementConfiguration(
            kind: .clockTime,
            frame: NormalizedRect(x: 0.05, y: 0.3, width: 0.8, height: 0.2),
            textScale: 0.6
        )]
        let renderer = OverlayFrameRenderer()
        let context = CIContext(options: [.useSoftwareRenderer: true])

        func pixels() throws -> Data {
            let image = try XCTUnwrap(renderer.render(
                size: CGSize(width: 640, height: 360),
                configuration: configuration,
                sample: nil,
                route: [],
                activityStart: nil,
                clockTime: timestamp
            ))
            let cgImage = try XCTUnwrap(context.createCGImage(image, from: image.extent))
            return try XCTUnwrap(cgImage.dataProvider?.data as Data?)
        }

        let smallerText = try pixels()
        configuration.elements[0].textScale = 1.4
        let largerText = try pixels()
        XCTAssertNotEqual(smallerText, largerText)

        configuration.elements[0].backgroundOpacity = 0.7
        let withBackground = try pixels()
        XCTAssertNotEqual(largerText, withBackground)
    }

    func test每张卡片单位切换会改变导出数值且不影响其他卡片() throws {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = ActivitySample(
            timestamp: timestamp.addingTimeInterval(300),
            distanceMeters: 1_609.344,
            speedMetersPerSecond: 1_609.344 / 480,
            altitudeMeters: 100,
            ascentMeters: 30
        )
        let renderer = OverlayFrameRenderer()
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let size = CGSize(width: 640, height: 360)

        func pixels(_ configuration: OverlayConfiguration) throws -> Data {
            let image = try XCTUnwrap(renderer.render(
                size: size,
                configuration: configuration,
                sample: sample,
                route: [],
                activityStart: timestamp,
                clockTime: timestamp
            ))
            let cgImage = try XCTUnwrap(
                context.createCGImage(image, from: image.extent)
            )
            return try XCTUnwrap(cgImage.dataProvider?.data as Data?)
        }

        for preset in [
            OverlayTemplatePreset.runningFocus,
            .sport,
            .stadiumLive
        ] {
            for (kind, unit) in [
                (OverlayElementKind.pace, OverlayMeasurementUnit.miles),
                (.distance, .miles),
                (.altitude, .feet),
                (.ascent, .feet)
            ] {
                var configuration = OverlayConfiguration.preset(preset)
                configuration.elements = [
                    OverlayElementConfiguration(
                        kind: kind,
                        frame: NormalizedRect(
                            x: 0.1, y: 0.2, width: 0.65, height: 0.35
                        )
                    )
                ]
                let metricPixels = try pixels(configuration)
                configuration.elements[0].measurementUnit = unit
                XCTAssertNotEqual(
                    metricPixels,
                    try pixels(configuration),
                    "\(preset) 的 \(kind) 应随单位切换改变导出文字"
                )
            }
        }
    }

    func test时钟与运动时长格式切换会改变导出图层() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = ActivitySample(timestamp: start.addingTimeInterval(1_354))
        let renderer = OverlayFrameRenderer()
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let size = CGSize(width: 640, height: 360)

        func pixels(_ configuration: OverlayConfiguration) throws -> Data {
            let image = try XCTUnwrap(renderer.render(
                size: size,
                configuration: configuration,
                sample: sample,
                route: [],
                activityStart: start,
                clockTime: sample.timestamp
            ))
            let cgImage = try XCTUnwrap(
                context.createCGImage(image, from: image.extent)
            )
            return try XCTUnwrap(cgImage.dataProvider?.data as Data?)
        }

        for preset in [
            OverlayTemplatePreset.runningFocus, .sport, .stadiumLive
        ] {
            var configuration = OverlayConfiguration.preset(preset)
            configuration.elements = [
                OverlayElementConfiguration(
                    kind: .clockTime,
                    frame: NormalizedRect(x: 0.1, y: 0.2, width: 0.75, height: 0.2)
                )
            ]
            let dateTimePixels = try pixels(configuration)
            configuration.elements[0].clockDisplay = .time
            XCTAssertNotEqual(dateTimePixels, try pixels(configuration))

            configuration.elements = [
                OverlayElementConfiguration(
                    kind: .elapsedTime,
                    frame: NormalizedRect(x: 0.1, y: 0.2, width: 0.75, height: 0.2)
                )
            ]
            let adaptivePixels = try pixels(configuration)
            configuration.elements[0].durationDisplay = .hoursMinutesSeconds
            XCTAssertNotEqual(adaptivePixels, try pixels(configuration))
        }
    }
}
