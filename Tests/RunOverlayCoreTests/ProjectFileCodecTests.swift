import Foundation
import XCTest
@testable import RunOverlayCore

final class ProjectFileCodecTests: XCTestCase {
    func test清空运动数据保留视频与蒙层且编码后不残留样本() throws {
        let video = VideoItem(
            fileName: "跑步.mp4",
            fileURL: URL(fileURLWithPath: "/素材/跑步.mp4"),
            metadata: VideoAssetMetadata(
                durationSeconds: 10,
                dimensions: PixelDimensions(width: 1_920, height: 1_080),
                frameRate: 30,
                capturedAt: nil,
                hasAudio: true,
                container: "MP4",
                fileSizeBytes: 100
            )
        )
        let source = ActivitySource(
            fileName: "运动.gpx",
            fileURL: URL(fileURLWithPath: "/素材/运动.gpx"),
            kind: .gpx
        )
        var project = RunOverlayProject(
            activitySource: source,
            activitySamples: [
                ActivitySample(timestamp: Date(timeIntervalSince1970: 1_000))
            ],
            videos: [video]
        )
        let originalOverlay = project.overlay
        project.clearActivity()
        XCTAssertNil(project.activitySource)
        XCTAssertTrue(project.activitySamples.isEmpty)
        XCTAssertEqual(project.videos, [video])
        XCTAssertEqual(project.overlay, originalOverlay)
        let restored = try ProjectFileCodec().decode(
            ProjectFileCodec().encode(project)
        )
        XCTAssertNil(restored.activitySource)
        XCTAssertTrue(restored.activitySamples.isEmpty)
        XCTAssertEqual(restored.videos, [video])
    }

    func test复制封面文字保留属性并生成可独立保存的图层() throws {
        let original = CoverTextLayer(
            text: "晨跑",
            position: CoverPoint(x: 0.9, y: 0.3),
            fontName: "PingFangSC-Regular",
            isBold: true,
            isItalic: true,
            fontHeight: 0.2,
            rotationDegrees: 18,
            colorHex: "#FFAA33",
            strokeHex: "#172122",
            strokeWidth: 0.08,
            shadowOpacity: 0.3,
            depth: .behindSelectedPeople,
            occlusionStrength: 0.75,
            selectedPeople: [CoverPoint(x: 0.4, y: 0.6)]
        )
        let other = CoverTextLayer(text: "终点")
        var cover = VideoCover(
            source: .videoFrame(CoverVideoFrame(seconds: 2)),
            textLayers: [original, other],
            exportedImage: CoverImageResource(
                fileURL: URL(fileURLWithPath: "/封面/已导出.png")
            )
        )
        XCTAssertNil(cover.duplicateTextLayer(id: UUID()))
        XCTAssertEqual(cover.textLayers.count, 2)
        XCTAssertNotNil(cover.exportedImage)

        let copy = try XCTUnwrap(cover.duplicateTextLayer(id: original.id))
        XCTAssertEqual(cover.textLayers.map(\.id), [original.id, copy.id, other.id])
        XCTAssertNotEqual(copy.id, original.id)
        var matchingPosition = copy
        matchingPosition.id = original.id
        matchingPosition.position = original.position
        XCTAssertEqual(matchingPosition, original)
        XCTAssertEqual(copy.position.x, 0.865, accuracy: 0.000_001)
        XCTAssertEqual(copy.position.y, 0.335, accuracy: 0.000_001)
        XCTAssertEqual(cover.textLayers[0], original)
        XCTAssertNil(cover.exportedImage)

        cover.textLayers[1].text = "另一个标题"
        XCTAssertEqual(cover.textLayers[0].text, "晨跑")
        let restored = try JSONDecoder().decode(
            VideoCover.self,
            from: JSONEncoder().encode(cover)
        )
        XCTAssertEqual(restored, cover)
    }

    func test再次打开视频帧封面刷新到当前时间且保留文字() {
        let layer = CoverTextLayer(
            text: "周末跑步",
            position: CoverPoint(x: 0.33, y: 0.57),
            rotationDegrees: 24,
            depth: .behindSelectedPeople,
            selectedPeople: [CoverPoint(x: 0.45, y: 0.6)]
        )
        let exported = CoverImageResource(
            fileURL: URL(fileURLWithPath: "/封面/已导出.png")
        )
        var cover = VideoCover(
            source: .videoFrame(CoverVideoFrame(seconds: 2)),
            textLayers: [layer],
            exportedImage: exported
        )
        XCTAssertTrue(cover.refreshVideoFrame(CoverVideoFrame(seconds: 9.5)))
        if case let .videoFrame(frame) = cover.source {
            XCTAssertEqual(frame.seconds, 9.5)
        } else {
            XCTFail("应该仍以视频帧为封面来源")
        }
        XCTAssertEqual(cover.textLayers[0].text, layer.text)
        XCTAssertEqual(cover.textLayers[0].position, layer.position)
        XCTAssertEqual(cover.textLayers[0].rotationDegrees, layer.rotationDegrees)
        XCTAssertTrue(cover.textLayers[0].selectedPeople.isEmpty)
        XCTAssertNil(cover.exportedImage)
        XCTAssertFalse(cover.refreshVideoFrame(CoverVideoFrame(seconds: 9.5)))
    }

    func test导入图片作为封面时重新打开不会替换底图() {
        let imported = CoverImageResource(
            fileURL: URL(fileURLWithPath: "/封面/自选图片.png")
        )
        let exported = CoverImageResource(
            fileURL: URL(fileURLWithPath: "/封面/已导出.png")
        )
        var cover = VideoCover(
            source: .image(imported),
            textLayers: [CoverTextLayer(text: "晨跑")],
            exportedImage: exported
        )
        XCTAssertFalse(cover.refreshVideoFrame(CoverVideoFrame(seconds: 12)))
        XCTAssertEqual(cover.source, .image(imported))
        XCTAssertEqual(cover.exportedImage, exported)
    }

    func test封面文字与人物选择随视频保存且旧项目仍能打开() throws {
        var project = RunOverlayProject(videos: [
            VideoItem(
                fileName: "跑步.mp4",
                fileURL: URL(fileURLWithPath: "/素材/跑步.mp4"),
                metadata: VideoAssetMetadata(
                    durationSeconds: 10,
                    dimensions: PixelDimensions(width: 1_920, height: 1_080),
                    frameRate: 30,
                    capturedAt: nil,
                    hasAudio: true,
                    container: "MP4",
                    fileSizeBytes: 100
                )
            )
        ])
        let codec = ProjectFileCodec()
        XCTAssertNil(try codec.decode(codec.encode(project)).videos.first?.cover)
        let cover = VideoCover(
            source: .videoFrame(CoverVideoFrame(
                seconds: 2.5,
                aspectRatio: .portrait9x16,
                maximumHeight: 720,
                rotation: .clockwise90
            )),
            textLayers: [
                CoverTextLayer(
                    text: "晨跑",
                    isBold: true,
                    isItalic: true,
                    rotationDegrees: 32,
                    depth: .behindSelectedPeople,
                    occlusionStrength: 0.45,
                    selectedPeople: [CoverPoint(x: 0.4, y: 0.6)]
                )
            ]
        )
        project.videos[0].cover = cover
        XCTAssertEqual(try codec.decode(codec.encode(project)).videos[0].cover, cover)
        let stored = try JSONSerialization.jsonObject(
            with: codec.encode(project)
        ) as? [String: Any]
        var legacy = try XCTUnwrap(stored)
        var videos = try XCTUnwrap(legacy["videos"] as? [[String: Any]])
        var firstVideo = videos[0]
        var coverJSON = try XCTUnwrap(firstVideo["cover"] as? [String: Any])
        var layers = try XCTUnwrap(coverJSON["textLayers"] as? [[String: Any]])
        layers[0].removeValue(forKey: "occlusionStrength")
        layers[0].removeValue(forKey: "rotationDegrees")
        layers[0].removeValue(forKey: "isBold")
        layers[0].removeValue(forKey: "isItalic")
        coverJSON["textLayers"] = layers
        firstVideo["cover"] = coverJSON
        videos[0] = firstVideo
        legacy["videos"] = videos
        let restored = try codec.decode(
            JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertEqual(
            restored.videos[0].cover?.textLayers.first?.occlusionStrength,
            1
        )
        XCTAssertEqual(
            restored.videos[0].cover?.textLayers.first?.rotationDegrees,
            0
        )
        XCTAssertEqual(
            restored.videos[0].cover?.textLayers.first?.isBold,
            true
        )
        XCTAssertEqual(
            restored.videos[0].cover?.textLayers.first?.isItalic,
            false
        )
    }

    func test项目可以完整编码和解码() throws {
        let original = RunOverlayProject(
            name: "上海晨跑",
            overlay: .preset(.technology),
            unitSystem: .metric,
            smoothingLevel: .light
        )
        let codec = ProjectFileCodec()

        let data = try codec.encode(original)
        let decoded = try codec.decode(data)

        XCTAssertEqual(decoded, original)
    }

    func test视频文字语言随项目保存且不依赖界面语言() throws {
        var project = RunOverlayProject()
        project.exportSettings.videoTextLanguage = .english
        let codec = ProjectFileCodec()
        let restored = try codec.decode(codec.encode(project))

        XCTAssertEqual(restored.exportSettings.videoTextLanguage, .english)
        let interfaceLanguage = RunOverlayLocalization.language
        defer { RunOverlayLocalization.language = interfaceLanguage }
        RunOverlayLocalization.language = .chineseSimplified
        XCTAssertEqual(
            StadiumLiveStyle.label(
                for: .pace,
                language: restored.exportSettings.videoTextLanguage
            ),
            "PACE"
        )
        RunOverlayLocalization.language = .english
        XCTAssertEqual(
            StadiumLiveStyle.label(for: .pace, language: .chinese),
            "配速"
        )
    }

    func test时钟图层写入项目且旧项目不被自动覆盖() throws {
        var project = RunOverlayProject()
        XCTAssertEqual(
            project.overlay.elements.filter { $0.kind == .clockTime }.count,
            1
        )
        project.overlay.elements.removeAll { $0.kind == .clockTime }

        let decoded = try ProjectFileCodec().decode(
            ProjectFileCodec().encode(project)
        )

        XCTAssertFalse(
            decoded.overlay.elements.contains { $0.kind == .clockTime }
        )
        XCTAssertEqual(
            OverlayConfiguration.clockTimeElement().kind,
            .clockTime
        )
    }

    func test图层卡片的显隐和独立编辑参数随项目保存() throws {
        var project = RunOverlayProject()
        let firstID = project.overlay.elements[0].id
        let secondID = project.overlay.elements[1].id
        let distanceIndex = try XCTUnwrap(
            project.overlay.elements.firstIndex { $0.kind == .distance }
        )
        let paceIndex = try XCTUnwrap(
            project.overlay.elements.firstIndex { $0.kind == .pace }
        )
        let durationIndex = try XCTUnwrap(
            project.overlay.elements.firstIndex { $0.kind == .elapsedTime }
        )
        let clockIndex = try XCTUnwrap(
            project.overlay.elements.firstIndex { $0.kind == .clockTime }
        )
        project.overlay.elements[0].isVisible = false
        project.overlay.elements[0].opacity = 0.43
        project.overlay.elements[0].backgroundOpacity = 0.18
        project.overlay.elements[0].textScale = 1.35
        project.overlay.elements[distanceIndex].measurementUnit = .miles
        project.overlay.elements[paceIndex].measurementUnit = .kilometers
        project.overlay.elements[durationIndex].durationDisplay = .adaptive
        project.overlay.elements[clockIndex].clockDisplay = .time
        project.overlay.elements[0].frame = NormalizedRect(
            x: 0.12, y: 0.08, width: 0.28, height: 0.25
        )
        let originalSecond = project.overlay.elements[1]

        let codec = ProjectFileCodec()
        let restored = try codec.decode(codec.encode(project))
        let first = try XCTUnwrap(restored.overlay.elements.first {
            $0.id == firstID
        })
        let second = try XCTUnwrap(restored.overlay.elements.first {
            $0.id == secondID
        })

        XCTAssertFalse(first.isVisible)
        XCTAssertEqual(first.opacity, 0.43)
        XCTAssertEqual(first.backgroundOpacity, 0.18)
        XCTAssertEqual(first.textScale, 1.35)
        XCTAssertEqual(
            first.frame,
            NormalizedRect(x: 0.12, y: 0.08, width: 0.28, height: 0.25)
        )
        XCTAssertEqual(
            restored.overlay.elements.first(where: { $0.kind == .distance })?
                .effectiveMeasurementUnit,
            .miles
        )
        XCTAssertEqual(
            restored.overlay.elements.first(where: { $0.kind == .pace })?
                .effectiveMeasurementUnit,
            .kilometers
        )
        XCTAssertEqual(
            restored.overlay.elements.first(where: { $0.kind == .clockTime })?
                .clockDisplay,
            .time
        )
        XCTAssertEqual(
            restored.overlay.elements.first(where: { $0.kind == .elapsedTime })?
                .durationDisplay,
            .adaptive
        )
        XCTAssertEqual(second, originalSecond)
    }

    func test所有图层卡片在每套模板中都可创建并保存() throws {
        XCTAssertEqual(
            Set(OverlayElementKind.cardOrder),
            Set(OverlayElementKind.allCases)
        )
        for preset in OverlayTemplatePreset.allCases {
            var configuration = OverlayConfiguration.preset(preset)
            let original = configuration.elements
            for kind in OverlayElementKind.cardOrder
            where !configuration.elements.contains(where: { $0.kind == kind }) {
                var element = configuration.newElement(for: kind)
                element.isVisible = false
                configuration.elements.append(element)
            }
            XCTAssertEqual(
                Set(configuration.elements.map(\.kind)),
                Set(OverlayElementKind.allCases),
                "\(preset)"
            )
            XCTAssertEqual(
                configuration.elements.prefix(original.count).map(\.id),
                original.map(\.id),
                "\(preset) 原有图层应保持不变"
            )
            for element in configuration.elements {
                let frame = element.frame
                XCTAssertGreaterThanOrEqual(frame.x, 0, "\(preset)")
                XCTAssertGreaterThanOrEqual(frame.y, 0, "\(preset)")
                XCTAssertLessThanOrEqual(frame.x + frame.width, 1, "\(preset)")
                XCTAssertLessThanOrEqual(frame.y + frame.height, 1, "\(preset)")
            }
            let project = RunOverlayProject(overlay: configuration)
            let codec = ProjectFileCodec()
            let restored = try codec.decode(codec.encode(project))
            XCTAssertEqual(restored.overlay, configuration, "\(preset)")
        }
    }

    func test三套内置模板初始布局紧凑且互不重叠() throws {
        for preset in [
            OverlayTemplatePreset.minimal,
            .sport,
            .technology
        ] {
            let elements = OverlayConfiguration.preset(preset).elements
            let route = try XCTUnwrap(elements.first { $0.kind == .route })
            let pace = try XCTUnwrap(elements.first { $0.kind == .pace })
            let heartRate = try XCTUnwrap(elements.first { $0.kind == .heartRate })
            let distance = try XCTUnwrap(elements.first { $0.kind == .distance })
            let clock = try XCTUnwrap(elements.first { $0.kind == .clockTime })

            XCTAssertLessThan(route.frame.x, 0.1)
            XCTAssertLessThan(route.frame.y, 0.1)
            XCTAssertLessThanOrEqual(route.frame.width, 0.22)
            XCTAssertLessThanOrEqual(route.frame.height, 0.22)
            XCTAssertLessThanOrEqual(route.frame.y + route.frame.height, pace.frame.y)
            XCTAssertEqual(pace.frame.x, heartRate.frame.x)
            XCTAssertEqual(heartRate.frame.x, distance.frame.x)
            XCTAssertLessThanOrEqual(pace.frame.y + pace.frame.height, heartRate.frame.y)
            XCTAssertLessThanOrEqual(
                heartRate.frame.y + heartRate.frame.height,
                distance.frame.y
            )
            XCTAssertGreaterThan(clock.frame.x, 0.6)
            XCTAssertLessThanOrEqual(clock.frame.width, 0.28)
            XCTAssertLessThanOrEqual(clock.frame.height, 0.10)
            XCTAssertLessThanOrEqual(clock.frame.x + clock.frame.width, 1)
            XCTAssertLessThanOrEqual(clock.frame.y + clock.frame.height, 1)
        }
    }

    func test拒绝未来版本项目() throws {
        var project = RunOverlayProject()
        project.schemaVersion = RunOverlayProject.currentSchemaVersion + 1
        let codec = ProjectFileCodec()
        let data = try codec.encode(project)

        XCTAssertThrowsError(try codec.decode(data)) { error in
            guard case ProjectFileCodecError.unsupportedSchema = error else {
                return XCTFail("返回了错误的错误类型：\(error)")
            }
        }
    }

    func test旧项目缺少卡片专属属性时仍可解码() throws {
        let original = RunOverlayProject()
        let encoded = try ProjectFileCodec().encode(original)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var overlay = try XCTUnwrap(json["overlay"] as? [String: Any])
        var elements = try XCTUnwrap(overlay["elements"] as? [[String: Any]])
        elements = elements.map { element in
            var legacyElement = element
            legacyElement.removeValue(forKey: "backgroundOpacity")
            legacyElement.removeValue(forKey: "textScale")
            legacyElement.removeValue(forKey: "measurementUnit")
            legacyElement.removeValue(forKey: "clockDisplay")
            legacyElement.removeValue(forKey: "durationDisplay")
            return legacyElement
        }
        overlay["elements"] = elements
        json["overlay"] = overlay
        var exportSettings = try XCTUnwrap(json["exportSettings"] as? [String: Any])
        exportSettings.removeValue(forKey: "aspectRatio")
        exportSettings.removeValue(forKey: "videoTextLanguage")
        json["exportSettings"] = exportSettings
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try ProjectFileCodec().decode(legacyData)

        XCTAssertEqual(
            decoded.overlay.elements.map(\.backgroundOpacity),
            Array(repeating: nil, count: decoded.overlay.elements.count)
        )
        XCTAssertEqual(
            decoded.overlay.elements.first?.backgroundOpacity ??
                decoded.overlay.preset.defaultBackgroundOpacity,
            decoded.overlay.preset.defaultBackgroundOpacity
        )
        XCTAssertTrue(decoded.overlay.elements.allSatisfy { $0.textScale == 1 })
        XCTAssertTrue(decoded.overlay.elements.allSatisfy { $0.measurementUnit == nil })
        XCTAssertTrue(decoded.overlay.elements.allSatisfy {
            $0.clockDisplay == .dateTime
        })
        XCTAssertTrue(decoded.overlay.elements.allSatisfy {
            $0.durationDisplay == .adaptive
        })
        XCTAssertEqual(
            decoded.overlay.elements.first(where: { $0.kind == .pace })?
                .effectiveMeasurementUnit,
            .kilometers
        )
        XCTAssertEqual(decoded.exportSettings.aspectRatio, .source)
        XCTAssertEqual(decoded.exportSettings.videoTextLanguage, .chinese)
    }

    func test比例预设生成符合短边分辨率的偶数尺寸() {
        let source = PixelDimensions(width: 3_840, height: 2_160)

        XCTAssertEqual(
            ExportAspectRatio.landscape16x9.outputDimensions(source: source),
            PixelDimensions(width: 1_920, height: 1_080)
        )
        XCTAssertEqual(
            ExportAspectRatio.portrait9x16.outputDimensions(source: source),
            PixelDimensions(width: 1_080, height: 1_920)
        )
        XCTAssertEqual(
            ExportAspectRatio.square.outputDimensions(source: source),
            PixelDimensions(width: 1_080, height: 1_080)
        )
        XCTAssertEqual(
            ExportAspectRatio.portrait4x5.outputDimensions(source: source),
            PixelDimensions(width: 1_080, height: 1_350)
        )
        XCTAssertEqual(
            ExportAspectRatio.landscape4x3.outputDimensions(source: source),
            PixelDimensions(width: 1_440, height: 1_080)
        )
        XCTAssertEqual(
            ExportAspectRatio.portrait3x4.outputDimensions(source: source),
            PixelDimensions(width: 1_080, height: 1_440)
        )
        XCTAssertEqual(
            ExportAspectRatio.source.outputDimensions(source: source),
            PixelDimensions(width: 1_920, height: 1_080)
        )
    }

    func test项目往返会保留导出比例设置() throws {
        var project = RunOverlayProject()
        project.exportSettings.aspectRatio = .portrait9x16

        let decoded = try ProjectFileCodec().decode(
            ProjectFileCodec().encode(project)
        )

        XCTAssertEqual(decoded.exportSettings.aspectRatio, .portrait9x16)
    }

    func test项目往返会保留卡片背景透明度() throws {
        var project = RunOverlayProject()
        project.overlay.elements[0].backgroundOpacity = 0.27
        let codec = ProjectFileCodec()

        let decoded = try codec.decode(codec.encode(project))

        XCTAssertEqual(decoded.overlay.elements[0].backgroundOpacity, 0.27)
    }

    func test项目往返会保留视频对应的时间资源() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let sidecar = VideoTimeResource(
            fileName: "跑步.lrv",
            fileURL: URL(fileURLWithPath: "/素材/跑步.lrv"),
            resourceRelativePath: "素材/时间资源/跑步.lrv",
            capturedAt: capturedAt
        )
        let video = VideoItem(
            fileName: "跑步.mp4",
            fileURL: URL(fileURLWithPath: "/素材/跑步.mp4"),
            metadata: VideoAssetMetadata(
                durationSeconds: 5,
                dimensions: PixelDimensions(width: 960, height: 540),
                frameRate: 30,
                capturedAt: nil,
                hasAudio: false,
                container: "MP4",
                fileSizeBytes: 123
            ),
            timeResource: sidecar
        )
        let project = RunOverlayProject(videos: [video])
        let codec = ProjectFileCodec()

        let decoded = try codec.decode(codec.encode(project))

        XCTAssertEqual(decoded.videos.first?.timeResource, sidecar)
        XCTAssertEqual(decoded.videos.first?.effectiveCapturedAt, capturedAt)
    }
}
