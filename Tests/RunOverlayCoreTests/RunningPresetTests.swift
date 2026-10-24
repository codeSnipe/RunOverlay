@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import RunOverlayCore

final class RunningPresetTests: XCTestCase {
    private let runningPresets: [OverlayTemplatePreset] = [
        .runningFocus,
        .track,
        .finishLine,
        .trail,
        .nightRun
    ]

    func test旧版模板标识和布局保持不变() throws {
        XCTAssertEqual(OverlayTemplatePreset.minimal.rawValue, "minimal")
        XCTAssertEqual(OverlayTemplatePreset.sport.rawValue, "sport")
        XCTAssertEqual(OverlayTemplatePreset.technology.rawValue, "technology")
        XCTAssertEqual(
            try JSONDecoder().decode(
                OverlayTemplatePreset.self,
                from: Data(#""technology""#.utf8)
            ),
            .technology
        )

        for preset in [
            OverlayTemplatePreset.minimal,
            .sport,
            .technology
        ] {
            let configuration = OverlayConfiguration.preset(preset)
            XCTAssertEqual(configuration.elements.count, 5)
            XCTAssertEqual(
                configuration.elements.map(\.kind),
                [.route, .pace, .heartRate, .distance, .clockTime]
            )
        }
    }

    func test跑步聚焦成为内置默认且参考构图保持无底板() throws {
        let project = RunOverlayProject()
        let overlay = project.overlay
        XCTAssertEqual(overlay.preset, .runningFocus)
        XCTAssertEqual(overlay.preset.defaultBackgroundOpacity, 0)
        XCTAssertEqual(overlay.accentHex, "#FFFFFF")
        XCTAssertEqual(overlay.elements.filter(\.isVisible).map(\.kind), [
            .route, .distance, .pace, .elapsedTime, .heartRate, .progress, .clockTime
        ])
        XCTAssertTrue(overlay.elements.allSatisfy {
            $0.kind == .progress ? $0.backgroundOpacity == 0.35 :
                $0.backgroundOpacity == nil
        })
        let clock = try XCTUnwrap(overlay.elements.first { $0.kind == .clockTime })
        XCTAssertTrue(clock.isVisible)
        XCTAssertEqual(clock.clockDisplay, .dateTime)
        XCTAssertEqual(clock.textScale, 1.1)
        XCTAssertEqual(clock.frame.x + clock.frame.width / 2, 0.86, accuracy: 0.000_001)
        XCTAssertEqual(clock.frame.y + clock.frame.height / 2, 0.91, accuracy: 0.000_001)
        XCTAssertEqual(clock.frame.width, 0.26, accuracy: 0.000_001)
        XCTAssertEqual(clock.frame.height, 0.08, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(clock.frame.y + clock.frame.height, 1)
        XCTAssertEqual(
            RunOverlayFormatters.clock(
                Date(timeIntervalSince1970: 1_800_000_000),
                display: clock.clockDisplay,
                timeZone: TimeZone(secondsFromGMT: 0)!
            ),
            "2027-01-15 08:00:00"
        )
        let leftColumn = overlay.elements.filter {
            $0.isVisible && $0.kind != .progress && $0.kind != .clockTime
        }
        XCTAssertTrue(zip(leftColumn, leftColumn.dropFirst()).allSatisfy {
            $0.frame.y < $1.frame.y
        })
        XCTAssertTrue(leftColumn.allSatisfy {
            $0.frame.x <= 0.025 && $0.frame.x + $0.frame.width <= 0.255
        })
        let progress = try XCTUnwrap(overlay.elements.first { $0.kind == .progress })
        let routeFrame = try XCTUnwrap(leftColumn.first?.frame)
        XCTAssertEqual(progress.frame.x + progress.frame.width / 2, 0.5)
        XCTAssertLessThan(progress.frame.y, 0.1)
        XCTAssertGreaterThanOrEqual(
            clock.frame.y,
            progress.frame.y + progress.frame.height
        )
        XCTAssertGreaterThan(clock.frame.y, 0.8)
        XCTAssertLessThanOrEqual(clock.frame.y + clock.frame.height, 1)
        XCTAssertTrue(leftColumn.dropFirst().allSatisfy { $0.textScale == 0.88 })
        XCTAssertGreaterThanOrEqual(
            progress.frame.x,
            routeFrame.x + routeFrame.width
        )
        let restored = try ProjectFileCodec().decode(
            ProjectFileCodec().encode(project)
        )
        XCTAssertEqual(restored.overlay, overlay)
        XCTAssertEqual(OverlayConfiguration.preset(.sport).elements.map(\.kind), [
            .route, .pace, .heartRate, .distance, .clockTime
        ])
    }

    func test跑步聚焦数字和标签格式() {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = ActivitySample(
            timestamp: started.addingTimeInterval(1_354),
            distanceMeters: 5_880,
            speedMetersPerSecond: 1_000.0 / 343,
            heartRate: 148
        )
        XCTAssertEqual(RunningFocusStyle.value(
            for: .distance, sample: sample,
            activityStart: started, clockTime: nil
        ), "5.88")
        XCTAssertEqual(RunningFocusStyle.value(
            for: .pace, sample: sample,
            activityStart: started, clockTime: nil
        ), "05′43″")
        XCTAssertEqual(RunningFocusStyle.value(
            for: .elapsedTime, sample: sample,
            activityStart: started, clockTime: nil
        ), "00:22:34")
        XCTAssertEqual(RunningFocusStyle.value(
            for: .heartRate, sample: sample,
            activityStart: started, clockTime: nil
        ), "148")
        XCTAssertEqual(RunningFocusStyle.label(
            for: .heartRate, language: .chinese
        ), "心率")
        XCTAssertEqual(RunningFocusStyle.label(
            for: .heartRate, language: .english
        ), "HEART RATE")
        XCTAssertEqual(RunningFocusStyle.label(
            for: .pace, language: .chinese
        ), "配速")
        XCTAssertEqual(RunningFocusStyle.label(
            for: .pace, language: .english
        ), "PACE")
        XCTAssertEqual(RunningFocusStyle.value(
            for: .distance, sample: nil,
            activityStart: nil, clockTime: nil
        ), "—")
    }

    func test跑步聚焦时钟不依赖运动采样并随时间更新() throws {
        var configuration = OverlayConfiguration.preset(.runningFocus)
        configuration.elements = configuration.elements.filter { $0.kind == .clockTime }
        let clock = try XCTUnwrap(configuration.elements.first)
        XCTAssertTrue(clock.isVisible)
        XCTAssertEqual(clock.clockDisplay, .dateTime)

        let renderer = OverlayFrameRenderer()
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        func pixels(at date: Date) throws -> Data {
            let image = try XCTUnwrap(renderer.render(
                size: CGSize(width: 960, height: 540),
                configuration: configuration,
                sample: nil,
                route: [],
                activityStart: nil,
                clockTime: date
            ))
            let cgImage = try XCTUnwrap(context.createCGImage(image, from: image.extent))
            return try XCTUnwrap(cgImage.dataProvider?.data as Data?)
        }

        XCTAssertNotEqual(
            try pixels(at: timestamp),
            try pixels(at: timestamp.addingTimeInterval(1))
        )
    }

    func test卡片单位独立换算并区分可配置类型() {
        XCTAssertEqual(
            OverlayElementKind.pace.supportedMeasurementUnits,
            [.kilometers, .miles]
        )
        XCTAssertEqual(
            OverlayElementKind.altitude.supportedMeasurementUnits,
            [.meters, .feet]
        )
        XCTAssertTrue(OverlayElementKind.heartRate.supportedMeasurementUnits.isEmpty)

        let sample = ActivitySample(
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            distanceMeters: 1_609.344,
            speedMetersPerSecond: 1_609.344 / 480,
            altitudeMeters: 100,
            ascentMeters: 30
        )
        XCTAssertEqual(RunningFocusStyle.value(
            for: .distance, sample: sample,
            activityStart: nil, clockTime: nil, measurementUnit: .miles
        ), "1.00")
        XCTAssertEqual(RunningFocusStyle.value(
            for: .pace, sample: sample,
            activityStart: nil, clockTime: nil, measurementUnit: .miles
        ), "08′00″")
        XCTAssertEqual(RunningFocusStyle.label(
            for: .distance, language: .chinese, measurementUnit: .miles
        ), "英里")
        XCTAssertEqual(RunningFocusStyle.label(
            for: .pace, language: .english, measurementUnit: .miles
        ), "PACE /MI")
        XCTAssertEqual(StadiumLiveStyle.value(
            for: .distance, sample: sample, clockTime: nil,
            measurementUnit: .miles
        ), "1.00 MI")
        XCTAssertEqual(StadiumLiveStyle.value(
            for: .altitude, sample: sample, clockTime: nil,
            measurementUnit: .feet
        ), "328 FT")
        XCTAssertEqual(StadiumLiveStyle.value(
            for: .ascent, sample: sample, clockTime: nil,
            measurementUnit: .feet
        ), "98 FT")
        XCTAssertEqual(
            OverlayMeasurementFormatter.pace(
                speedMetersPerSecond: 0,
                unit: .miles
            )?.minutes,
            nil
        )
    }

    func test跑步聚焦横竖屏导出画面与语言切换() throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let route = [
            GeoCoordinate(latitude: 31.20, longitude: 121.41),
            GeoCoordinate(latitude: 31.21, longitude: 121.42),
            GeoCoordinate(latitude: 31.22, longitude: 121.40)
        ]
        let sample = ActivitySample(
            timestamp: started.addingTimeInterval(1_354),
            coordinate: route[1],
            distanceMeters: 5_880,
            speedMetersPerSecond: 1_000.0 / 343
        )
        let renderer = OverlayFrameRenderer()
        let context = CIContext(options: [.useSoftwareRenderer: true])
        for size in [
            CGSize(width: 854, height: 480),
            CGSize(width: 270, height: 480)
        ] {
            let chinese = try XCTUnwrap(renderer.render(
                size: size,
                configuration: .preset(.runningFocus),
                sample: sample,
                route: route,
                activityStart: started,
                videoTextLanguage: .chinese
            ))
            let english = try XCTUnwrap(renderer.render(
                size: size,
                configuration: .preset(.runningFocus),
                sample: sample,
                route: route,
                activityStart: started,
                videoTextLanguage: .english
            ))
            XCTAssertEqual(chinese.extent.size, size)
            let chineseImage = try XCTUnwrap(
                context.createCGImage(chinese, from: chinese.extent)
            )
            let englishImage = try XCTUnwrap(
                context.createCGImage(english, from: english.extent)
            )
            XCTAssertNotEqual(
                chineseImage.dataProvider?.data as Data?,
                englishImage.dataProvider?.data as Data?
            )
        }
    }

    func test跑步聚焦真实视频静帧视觉检查() throws {
        guard ProcessInfo.processInfo.environment["RUNOVERLAY_VISUAL_QA"] == "1" else {
            throw XCTSkip("仅在明确开启视觉检查时生成静帧")
        }
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let input = projectDirectory.appendingPathComponent(
            "demo/DJI_20261002111755_0086_D.MP4"
        )
        guard FileManager.default.isReadableFile(atPath: input.path) else {
            throw XCTSkip("当前工作区没有演示视频")
        }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: input))
        generator.appliesPreferredTrackTransform = true
        let videoFrame = try generator.copyCGImage(
            at: CMTime(seconds: 2, preferredTimescale: 600),
            actualTime: nil
        )
        let canvas = CGRect(x: 0, y: 0, width: 960, height: 540)
        let scale = max(
            canvas.width / CGFloat(videoFrame.width),
            canvas.height / CGFloat(videoFrame.height)
        )
        let source = CIImage(cgImage: videoFrame)
        let scaled = source.transformed(by: CGAffineTransform(
            scaleX: scale,
            y: scale
        ))
        let video = scaled.transformed(by: CGAffineTransform(
            translationX: (canvas.width - scaled.extent.width) / 2,
            y: (canvas.height - scaled.extent.height) / 2
        )).cropped(to: canvas)

        let start = try XCTUnwrap(VideoTimeResourceReader().capturedAt(
            from: input
        ))
        let route = [
            GeoCoordinate(latitude: 31.20, longitude: 121.40),
            GeoCoordinate(latitude: 31.205, longitude: 121.405),
            GeoCoordinate(latitude: 31.207, longitude: 121.409),
            GeoCoordinate(latitude: 31.204, longitude: 121.412),
            GeoCoordinate(latitude: 31.20, longitude: 121.41)
        ]
        let sample = ActivitySample(
            timestamp: start.addingTimeInterval(1_354),
            coordinate: route[3],
            distanceMeters: 5_880,
            speedMetersPerSecond: 1_000.0 / 343,
            heartRate: 148
        )
        let overlay = try XCTUnwrap(OverlayFrameRenderer().render(
            size: canvas.size,
            configuration: .preset(.runningFocus),
            sample: sample,
            activityProgress: ActivityProgress(
                fraction: 0.588,
                currentDistanceMeters: 5_880,
                totalDistanceMeters: 10_000
            ),
            route: route,
            activityStart: start,
            clockTime: sample.timestamp,
            videoTextLanguage: .chinese
        ))
        let composited = overlay.composited(over: video).cropped(to: canvas)
        let data = try XCTUnwrap(CIContext().pngRepresentation(
            of: composited,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ))
        let output = projectDirectory.appendingPathComponent(
            ".build/RunningFocusVisualQA.png"
        )
        try data.write(to: output, options: .atomic)
        let activityURL = projectDirectory.appendingPathComponent(
            "demo/480745612738855213.fit"
        )
        if FileManager.default.isReadableFile(atPath: activityURL.path) {
            let activity = try ActivityParser().parse(from: activityURL)
            let coordinates = activity.samples.compactMap(\.coordinate)
            let sample = try XCTUnwrap(activity.samples.first {
                $0.coordinate != nil
            })
            let realOverlay = try XCTUnwrap(OverlayFrameRenderer().render(
                size: canvas.size,
                configuration: .preset(.runningFocus),
                sample: sample,
                activityProgress: ActivityProgressCalculator(
                    samples: activity.samples
                ).progress(for: sample),
                route: coordinates,
                activityStart: activity.timeRange.start,
                clockTime: sample.timestamp
            ))
            let realImage = realOverlay.composited(over: video).cropped(to: canvas)
            let realData = try XCTUnwrap(CIContext().pngRepresentation(
                of: realImage,
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            ))
            try realData.write(
                to: projectDirectory.appendingPathComponent(
                    ".build/RunningFocusActualGPXVisualQA.png"
                ),
                options: .atomic
            )
        }
        print("跑步聚焦视觉检查：\(output.path)")
    }

    func test新增模板可以随项目保存和恢复() throws {
        let codec = ProjectFileCodec()
        for preset in runningPresets {
            let original = RunOverlayProject(
                overlay: .preset(preset)
            )
            let decoded = try codec.decode(codec.encode(original))
            XCTAssertEqual(decoded.overlay, original.overlay, "\(preset)")
        }
    }

    func test新增模板有独立配色并覆盖跑步核心数据() {
        XCTAssertEqual(Set(runningPresets.map(\.rawValue)).count, runningPresets.count)
        let accentColors = runningPresets.map {
            OverlayConfiguration.preset($0).accentHex
        }
        XCTAssertEqual(Set(accentColors).count, runningPresets.count)

        for preset in runningPresets where preset != .runningFocus {
            let configuration = OverlayConfiguration.preset(preset)
            let kinds = Set(configuration.elements.map(\.kind))
            XCTAssertTrue(kinds.isSuperset(of: [
                .route, .pace, .distance, .heartRate, .clockTime, .calories
            ]), "\(preset)")
            XCTAssertEqual(kinds.count, configuration.elements.count, "\(preset)")
            XCTAssertFalse(preset.displayName.isEmpty)
            XCTAssertFalse(preset.displayName.hasPrefix("template."))
        }
        for preset in [OverlayTemplatePreset.track, .trail] {
            XCTAssertTrue(
                OverlayConfiguration.preset(preset).elements.contains {
                    $0.kind == .ascent
                },
                "\(preset)"
            )
        }
    }

    func test新增模板名称在三种界面语言下可读() {
        let originalLanguage = RunOverlayLocalization.language
        defer {
            RunOverlayLocalization.language = originalLanguage
        }
        let translatedNames: [(RunOverlayLanguage, String)] = [
            (.chineseSimplified, "赛道节奏"),
            (.english, "Track Rhythm"),
            (.japanese, "トラックのリズム")
        ]
        for (language, expectedName) in translatedNames {
            RunOverlayLocalization.language = language
            XCTAssertEqual(OverlayTemplatePreset.track.displayName, expectedName)
            for preset in runningPresets {
                XCTAssertFalse(preset.displayName.hasPrefix("template."))
            }
        }
    }

    func test四种视频比例下新模板都在画面内且图层不重叠() {
        let frameSizes: [(width: Double, height: Double)] = [
            (1920, 1080),
            (1080, 1920),
            (1440, 1080),
            (1080, 1440)
        ]

        for preset in runningPresets {
            let elements = OverlayConfiguration.preset(preset).elements
            for frameSize in frameSizes {
                for element in elements {
                    let frame = element.frame
                    XCTAssertGreaterThanOrEqual(frame.x, 0, "\(preset)")
                    XCTAssertGreaterThanOrEqual(frame.y, 0, "\(preset)")
                    XCTAssertGreaterThan(frame.width, 0, "\(preset)")
                    XCTAssertGreaterThan(frame.height, 0, "\(preset)")
                    XCTAssertLessThanOrEqual(frame.x + frame.width, 1, "\(preset)")
                    XCTAssertLessThanOrEqual(frame.y + frame.height, 1, "\(preset)")
                    XCTAssertGreaterThanOrEqual(
                        frame.width * frameSize.width, 80, "\(preset)"
                    )
                    XCTAssertGreaterThanOrEqual(
                        frame.height * frameSize.height,
                        preset == .runningFocus ? 57 : 64,
                        "\(preset)"
                    )
                }

                for firstIndex in elements.indices {
                    for secondIndex in elements.indices where secondIndex > firstIndex {
                        let first = elements[firstIndex].frame
                        let second = elements[secondIndex].frame
                        let horizontalGap =
                            first.x + first.width <= second.x ||
                            second.x + second.width <= first.x
                        let verticalGap =
                            first.y + first.height <= second.y ||
                            second.y + second.height <= first.y
                        XCTAssertTrue(
                            horizontalGap || verticalGap,
                            "\(preset) 的 \(elements[firstIndex].kind) 和 " +
                                "\(elements[secondIndex].kind) 在 " +
                                "\(Int(frameSize.width))×\(Int(frameSize.height)) 中重叠"
                        )
                    }
                }
            }
        }
    }

    func test新模板为跑者保留中央画面() {
        for preset in runningPresets {
            let elements = OverlayConfiguration.preset(preset).elements
            let center = (x: 0.5, y: 0.5)
            XCTAssertFalse(elements.contains { element in
                let frame = element.frame
                return frame.x < center.x &&
                    frame.x + frame.width > center.x &&
                    frame.y < center.y &&
                    frame.y + frame.height > center.y
            }, "\(preset)")
        }
    }

    func test新模板在四种比例中均可渲染() throws {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let start = timestamp.addingTimeInterval(-1_140)
        let route = [
            GeoCoordinate(latitude: 31.20, longitude: 121.41),
            GeoCoordinate(latitude: 31.21, longitude: 121.42),
            GeoCoordinate(latitude: 31.22, longitude: 121.43)
        ]
        let sample = ActivitySample(
            timestamp: timestamp,
            coordinate: route[1],
            distanceMeters: 5_240,
            speedMetersPerSecond: 3.6,
            heartRate: 148,
            cadence: 172,
            altitudeMeters: 96,
            ascentMeters: 32,
            caloriesKilocalories: 287
        )
        let frameSizes = [
            CGSize(width: 320, height: 180),
            CGSize(width: 180, height: 320),
            CGSize(width: 240, height: 180),
            CGSize(width: 180, height: 240)
        ]
        let renderer = OverlayFrameRenderer()

        for preset in runningPresets {
            for frameSize in frameSizes {
                let rendered = try XCTUnwrap(
                    renderer.render(
                        size: frameSize,
                        configuration: .preset(preset),
                        sample: sample,
                        route: route,
                        activityStart: start,
                        clockTime: timestamp
                    ),
                    "\(preset) 在 \(frameSize) 无法生成图像"
                )
                XCTAssertEqual(rendered.extent.size, frameSize)
            }
        }
    }

    func test赛场实况布局与参考图一致且可以保存() throws {
        let configuration = OverlayConfiguration.preset(.stadiumLive)
        XCTAssertEqual(configuration.accentHex, "#FFFFFF")
        XCTAssertEqual(configuration.elements.map(\.kind), [
            .route, .pace, .calories, .heartRate, .altitude, .distance, .clockTime
        ])
        XCTAssertEqual(configuration.elements[0].backgroundOpacity, 0.52)
        XCTAssertEqual(configuration.preset.defaultBackgroundOpacity, 0)
        XCTAssertTrue(configuration.elements.allSatisfy {
            let frame = $0.frame
            return frame.x >= 0 && frame.y >= 0 &&
                frame.x + frame.width <= 1 &&
                frame.y + frame.height <= 1
        })
        let left = configuration.elements.prefix(4)
        let right = configuration.elements.suffix(3)
        XCTAssertTrue(left.allSatisfy { $0.frame.x + $0.frame.width < 0.5 })
        XCTAssertTrue(right.allSatisfy { $0.frame.x >= 0.5 })
        XCTAssertTrue(configuration.elements.dropFirst().allSatisfy {
            $0.frame.y > 0.5
        })
        let project = RunOverlayProject(overlay: configuration)
        XCTAssertEqual(
            try ProjectFileCodec().decode(ProjectFileCodec().encode(project)).overlay,
            configuration
        )
    }

    func test赛场实况数据格式与缺失值() {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = ActivitySample(
            timestamp: timestamp,
            distanceMeters: 2_960,
            speedMetersPerSecond: 1_000.0 / 469,
            heartRate: 165,
            altitudeMeters: 7,
            caloriesKilocalories: 21.8
        )
        XCTAssertEqual(
            StadiumLiveStyle.value(for: .pace, sample: sample, clockTime: timestamp),
            "7′49″"
        )
        XCTAssertEqual(
            StadiumLiveStyle.value(for: .calories, sample: sample, clockTime: timestamp),
            "21.8 KCAL"
        )
        XCTAssertEqual(
            StadiumLiveStyle.value(for: .distance, sample: sample, clockTime: timestamp),
            "2.96 KM"
        )
        XCTAssertEqual(
            StadiumLiveStyle.value(for: .altitude, sample: sample, clockTime: timestamp),
            "7 M"
        )
        XCTAssertEqual(
            StadiumLiveStyle.value(for: .heartRate, sample: sample, clockTime: timestamp),
            "165"
        )
        XCTAssertEqual(
            StadiumLiveStyle.value(for: .calories, sample: nil, clockTime: nil),
            "— KCAL"
        )
        XCTAssertTrue(
            StadiumLiveStyle.value(for: .clockTime, sample: nil, clockTime: timestamp)
                .contains("/")
        )
    }

    func test赛场实况所有可选数据都能显示数值与中文英文标签() {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = ActivitySample(
            timestamp: timestamp,
            cadence: 174,
            power: 268,
            ascentMeters: 32
        )
        for kind in [
            OverlayElementKind.elapsedTime, .cadence, .power, .ascent
        ] {
            XCTAssertFalse(StadiumLiveStyle.label(
                for: kind, language: .chinese
            ).isEmpty)
            XCTAssertFalse(StadiumLiveStyle.label(
                for: kind, language: .english
            ).isEmpty)
            XCTAssertFalse(StadiumLiveStyle.value(
                for: kind,
                sample: sample,
                clockTime: timestamp,
                activityStart: timestamp.addingTimeInterval(-60)
            ).isEmpty)
        }
        XCTAssertEqual(
            StadiumLiveStyle.value(
                for: .elapsedTime,
                sample: sample,
                clockTime: timestamp,
                activityStart: timestamp.addingTimeInterval(-60)
            ),
            "01:00"
        )
    }

    func test赛场实况在三种语言与横竖屏中可用() throws {
        let originalLanguage = RunOverlayLocalization.language
        defer { RunOverlayLocalization.language = originalLanguage }
        for (language, name) in [
            (RunOverlayLanguage.chineseSimplified, "赛场实况"),
            (.english, "Stadium Live"),
            (.japanese, "スタジアムライブ")
        ] {
            RunOverlayLocalization.language = language
            XCTAssertEqual(OverlayTemplatePreset.stadiumLive.displayName, name)
            XCTAssertFalse(StadiumLiveStyle.label(for: .pace).hasPrefix("stadium."))
        }

        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = ActivitySample(
            timestamp: timestamp,
            coordinate: GeoCoordinate(latitude: 31.2, longitude: 121.4),
            distanceMeters: 2_960,
            speedMetersPerSecond: 3.2,
            heartRate: 165,
            altitudeMeters: 7,
            caloriesKilocalories: 21.8
        )
        for size in [
            CGSize(width: 854, height: 480),
            CGSize(width: 270, height: 480)
        ] {
            let image = try XCTUnwrap(OverlayFrameRenderer().render(
                size: size,
                configuration: .preset(.stadiumLive),
                sample: sample,
                route: [
                    GeoCoordinate(latitude: 31.2, longitude: 121.4),
                    GeoCoordinate(latitude: 31.201, longitude: 121.402)
                ],
                activityStart: timestamp,
                clockTime: timestamp
            ))
            XCTAssertEqual(image.extent.size, size)
        }
    }

    func test赛场实况文字语言独立决定导出渲染() throws {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = ActivitySample(
            timestamp: timestamp,
            speedMetersPerSecond: 3.1,
            heartRate: 165,
            altitudeMeters: 7,
            caloriesKilocalories: 21.8
        )
        let renderer = OverlayFrameRenderer()
        let size = CGSize(width: 854, height: 480)
        let chinese = try XCTUnwrap(renderer.render(
            size: size,
            configuration: .preset(.stadiumLive),
            sample: sample,
            route: [],
            activityStart: timestamp,
            clockTime: timestamp,
            videoTextLanguage: .chinese
        ))
        let english = try XCTUnwrap(renderer.render(
            size: size,
            configuration: .preset(.stadiumLive),
            sample: sample,
            route: [],
            activityStart: timestamp,
            clockTime: timestamp,
            videoTextLanguage: .english
        ))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let chineseImage = try XCTUnwrap(
            context.createCGImage(chinese, from: chinese.extent)
        )
        let englishImage = try XCTUnwrap(
            context.createCGImage(english, from: english.extent)
        )
        XCTAssertNotEqual(
            chineseImage.dataProvider?.data as Data?,
            englishImage.dataProvider?.data as Data?
        )
    }
}
