import AppKit
import CoreImage
import CoreGraphics
import CoreText
import ImageIO
import XCTest
@testable import RunOverlayCore

final class CoverComposerTests: XCTestCase {
    func test单击文字保留选中目标而单击图片空白取消() {
        let size = CGSize(width: 800, height: 450)
        let first = CoverTextLayer(
            text: "晨跑",
            position: CoverPoint(x: 0.3, y: 0.4),
            fontName: "PingFangSC-Regular",
            isItalic: true,
            fontHeight: 0.12,
            rotationDegrees: 28
        )
        var top = first
        top.id = UUID()
        let frame = CoverComposer().textFrame(of: first, imageSize: size)
        let center = CGPoint(x: frame.midX * size.width, y: frame.midY * size.height)
        let hitTester = CoverTextHitTester()

        XCTAssertEqual(
            hitTester.layerID(at: center, in: size, layers: [first, top]),
            top.id,
            "重叠的文字应选择上层，不能误取消选中"
        )
        XCTAssertNil(hitTester.layerID(
            at: CGPoint(x: 760, y: 400),
            in: size,
            layers: [first, top]
        ))
        XCTAssertNil(hitTester.layerID(at: center, in: .zero, layers: [first]))
        XCTAssertNil(hitTester.layerID(
            at: center,
            in: size,
            layers: [CoverTextLayer(text: "")]
        ))
    }

    func test推荐配色恰好十组且只修改当前文字图层() {
        let recommendations = CoverTextColorPreset.recommendations
        XCTAssertEqual(recommendations.count, 10)
        XCTAssertEqual(Set(recommendations.map(\.id)).count, 10)
        XCTAssertEqual(
            Set(recommendations.map { "\($0.textHex)/\($0.strokeHex)" }).count,
            10
        )
        XCTAssertTrue(recommendations.allSatisfy {
            [$0.textHex, $0.strokeHex].allSatisfy { color in
                color.count == 7 &&
                    color.first == "#" &&
                    color.dropFirst().allSatisfy(\.isHexDigit)
            }
        })
        var first = CoverTextLayer(text: "跑步")
        let second = CoverTextLayer(text: "终点")
        first.apply(recommendations[2])
        XCTAssertEqual(first.colorHex, recommendations[2].textHex)
        XCTAssertEqual(first.strokeHex, recommendations[2].strokeHex)
        XCTAssertEqual(
            first.strokeWidth,
            CoverTextColorPreset.defaultStrokeWidth
        )
        XCTAssertEqual(second.colorHex, "#FFFFFF")
        XCTAssertEqual(second.strokeWidth, 0)
        first.strokeWidth = 0.012
        first.apply(recommendations[3])
        XCTAssertEqual(first.strokeWidth, 0.012)
        XCTAssertEqual(
            recommendations[3].strokeWidth(afterApplyingTo: 0.012),
            first.strokeWidth
        )
    }

    func test每组配色能渲染出示例汉字及描边() throws {
        let composer = CoverComposer()
        for preset in CoverTextColorPreset.recommendations {
            let sample = CoverTextLayer(
                text: "示例",
                fontName: "PingFangSC-Regular",
                fontHeight: 0.62,
                colorHex: preset.textHex,
                strokeHex: preset.strokeHex,
                strokeWidth: 0.05,
                shadowOpacity: 0
            )
            let image = try composer.renderTextOverlay(
                imageSize: CGSize(width: 128, height: 64),
                layer: sample
            )
            let pixels = try pixelBytes(image)
            let visible = stride(from: 3, to: pixels.count, by: 4)
                .filter { pixels[$0] > 25 }.count
            XCTAssertGreaterThan(visible, 300, "配色 \(preset.id) 必须能看到示例字")
        }
    }

    func test粗体斜体在字体变体存在时切换实际字面() {
        let base = CoverTextLayer(text: "RUN", fontName: "HelveticaNeue")
        var boldItalic = base
        boldItalic.isBold = true
        boldItalic.isItalic = true
        let originalName = CoverComposer.font(for: base, size: 30)
        let styledName = CoverComposer.font(for: boldItalic, size: 30)
        XCTAssertNotEqual(
            CTFontCopyPostScriptName(originalName) as String,
            CTFontCopyPostScriptName(styledName) as String
        )
        XCTAssertTrue(
            CTFontGetSymbolicTraits(styledName).contains(.traitBold)
        )
        XCTAssertTrue(
            CTFontGetSymbolicTraits(styledName).contains(.traitItalic)
        )
    }

    func test缺少斜体字面时仍绘制出可见倾斜效果() throws {
        let composer = CoverComposer()
        let size = CGSize(width: 800, height: 450)
        var layer = CoverTextLayer(
            text: "良渚天梯",
            fontName: "PingFangSC-Regular",
            fontHeight: 0.16,
            shadowOpacity: 0
        )
        let upright = try pixelBytes(
            composer.renderTextOverlay(imageSize: size, layer: layer)
        )
        layer.isItalic = true
        let italic = try pixelBytes(
            composer.renderTextOverlay(imageSize: size, layer: layer)
        )
        XCTAssertNotEqual(upright, italic)
        let bounds = composer.textFrame(of: layer, imageSize: size)
        XCTAssertGreaterThan(bounds.width, 0)
        let frame = CGRect(
            x: bounds.minX * size.width,
            y: bounds.minY * size.height,
            width: bounds.width * size.width,
            height: bounds.height * size.height
        ).insetBy(dx: -4, dy: -4)
        let pixels = try pixelBytes(
            composer.renderTextOverlay(imageSize: size, layer: layer)
        )
        var inside = 0
        var outside = 0
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) {
                let offset = (y * Int(size.width) + x) * 4
                guard pixels[offset + 3] > 35 else { continue }
                if frame.contains(CGPoint(x: x, y: y)) {
                    inside += 1
                } else {
                    outside += 1
                }
            }
        }
        XCTAssertGreaterThan(inside, 500)
        XCTAssertLessThan(outside, inside / 50)
    }

    func test封面字号上限支持大字() {
        XCTAssertEqual(CoverTextLayer.fontHeightRange.lowerBound, 0.02)
        XCTAssertGreaterThanOrEqual(CoverTextLayer.fontHeightRange.upperBound, 0.6)
        let big = CoverTextLayer(
            text: "RUN",
            fontHeight: CoverTextLayer.fontHeightRange.upperBound
        )
        let frame = CoverComposer().textFrame(
            of: big,
            imageSize: CGSize(width: 1_600, height: 900)
        )
        XCTAssertGreaterThan(frame.height, 0.5)
    }

    func test文字前景与人物遮挡按顺序渲染() throws {
        let cgImage = try demonstrationImage()
        let composer = CoverComposer()
        let people = try composer.detectPeople(in: cgImage)
        XCTAssertFalse(people.isEmpty)

        let text = CoverTextLayer(
            text: "RUN",
            position: CoverPoint(x: 0.5, y: 0.5),
            fontHeight: 0.16,
            colorHex: "#FFFF00",
            shadowOpacity: 0,
            depth: .front
        )
        let front = try composer.render(image: cgImage, layers: [text])
        var behindLayer = text
        behindLayer.depth = .behindAllPeople
        let behind = try composer.render(image: cgImage, layers: [behindLayer])
        XCTAssertEqual(front.width, cgImage.width)
        XCTAssertEqual(behind.height, cgImage.height)
        XCTAssertNotEqual(
            front.dataProvider?.data as Data?,
            behind.dataProvider?.data as Data?
        )
    }

    func test选中的人遮挡文字而其他人仍显示文字() throws {
        let image = try demonstrationImage()
        let composer = CoverComposer()
        let analysis = try CoverPeopleAnalysis(image: image)
        guard analysis.people.count >= 2 else {
            throw XCTSkip("演示静帧中少于两位可分割人物")
        }
        let layer = CoverTextLayer(
            text: "RUN RUN RUN RUN RUN RUN",
            position: CoverPoint(x: 0.5, y: 0.56),
            fontHeight: 0.18,
            colorHex: "#FFFF00",
            shadowOpacity: 0,
            depth: .front
        )
        let front = try composer.render(image: image, layers: [layer])
        var behindAll = layer
        behindAll.depth = .behindAllPeople
        let all = try composer.render(
            image: image,
            layers: [behindAll],
            people: analysis
        )

        let originalPixels = try pixelBytes(image)
        let frontPixels = try pixelBytes(front)
        let allPixels = try pixelBytes(all)
        let width = image.width
        var candidates: [Int: (CoverPoint, Int)] = [:]
        for y in stride(from: 40, to: image.height - 40, by: 4) {
            for x in stride(from: 40, to: image.width - 40, by: 4) {
                let offset = (y * width + x) * 4
                guard colorDistance(frontPixels, originalPixels, at: offset) > 60,
                      colorDistance(allPixels, originalPixels, at: offset) < 20 else {
                    continue
                }
                let point = CoverPoint(
                    x: (Double(x) + 0.5) / Double(width),
                    y: (Double(y) + 0.5) / Double(image.height)
                )
                if let id = analysis.id(at: point) {
                    let previous = candidates[id]?.1 ?? 0
                    candidates[id] = (point, previous + 1)
                }
            }
        }
        let visiblePeople = candidates.sorted { $0.value.1 > $1.value.1 }
        XCTAssertGreaterThanOrEqual(
            visiblePeople.count, 2,
            "文字需实际穿过至少两位人物，以校验单人和所有人遮挡区别"
        )
        guard visiblePeople.count >= 2 else { return }
        let selected = visiblePeople[0]
        let other = visiblePeople[1]
        var behindSelected = layer
        behindSelected.depth = .behindSelectedPeople
        behindSelected.selectedPeople = [selected.value.0]
        let selectedImage = try composer.render(
            image: image,
            layers: [behindSelected],
            people: analysis
        )
        let selectedPixels = try pixelBytes(selectedImage)
        let selectedOffset = pixelOffset(selected.value.0, in: image)
        let otherOffset = pixelOffset(other.value.0, in: image)
        let detachedText = try composer.renderTextOverlay(
            imageSize: CGSize(width: image.width, height: image.height),
            layer: behindSelected
        )
        let visibleMask = try XCTUnwrap(composer.visibleTextMask(
            imageSize: CGSize(width: image.width, height: image.height),
            layer: behindSelected,
            people: analysis
        ))
        let textPixels = try pixelBytes(detachedText)
        let maskPixels = try pixelBytes(visibleMask)
        XCTAssertGreaterThan(textPixels[selectedOffset + 3], 200)
        XCTAssertGreaterThan(textPixels[otherOffset + 3], 200)
        XCTAssertLessThan(maskPixels[selectedOffset + 3], 20)
        XCTAssertGreaterThan(maskPixels[otherOffset + 3], 235)
        XCTAssertLessThan(
            colorDistance(selectedPixels, originalPixels, at: selectedOffset), 20
        )
        XCTAssertLessThan(
            colorDistance(selectedPixels, frontPixels, at: otherOffset), 20
        )
        XCTAssertGreaterThan(
            colorDistance(allPixels, frontPixels, at: otherOffset), 60
        )
    }

    func test遮挡强度从文字可见到完全消失且预览与导出一致() throws {
        let image = try demonstrationImage()
        let composer = CoverComposer()
        let analysis = try CoverPeopleAnalysis(image: image)
        guard !analysis.people.isEmpty else {
            throw XCTSkip("演示静帧中没有可分割的人物")
        }
        var layer = CoverTextLayer(
            text: "RUN RUN RUN RUN RUN RUN",
            position: CoverPoint(x: 0.5, y: 0.56),
            fontHeight: 0.18,
            colorHex: "#FFFF00",
            shadowOpacity: 0,
            depth: .behindAllPeople
        )
        let sourcePixels = try pixelBytes(image)
        layer.occlusionStrength = 0
        let unoccluded = try pixelBytes(composer.render(
            image: image,
            layers: [layer],
            people: analysis
        ))
        layer.occlusionStrength = 0.5
        let intermediate = try pixelBytes(composer.render(
            image: image,
            layers: [layer],
            people: analysis
        ))
        layer.occlusionStrength = 1
        let hidden = try pixelBytes(composer.render(
            image: image,
            layers: [layer],
            people: analysis
        ))

        let size = CGSize(width: image.width, height: image.height)
        let fullMask = try XCTUnwrap(composer.visibleTextMask(
            imageSize: size,
            layer: layer,
            people: analysis
        ))
        layer.occlusionStrength = 0.5
        let halfMask = try XCTUnwrap(composer.visibleTextMask(
            imageSize: size,
            layer: layer,
            people: analysis
        ))
        layer.occlusionStrength = 0
        XCTAssertNil(try composer.visibleTextMask(
            imageSize: size,
            layer: layer,
            people: analysis
        ))
        let fullMaskPixels = try pixelBytes(fullMask)
        let halfMaskPixels = try pixelBytes(halfMask)

        var candidateOffset: Int?
        for y in stride(from: 40, to: image.height - 40, by: 4) {
            for x in stride(from: 40, to: image.width - 40, by: 4) {
                let offset = (y * image.width + x) * 4
                if colorDistance(unoccluded, sourcePixels, at: offset) > 120,
                   colorDistance(hidden, sourcePixels, at: offset) < 15,
                   fullMaskPixels[offset + 3] < 10 {
                    candidateOffset = offset
                    break
                }
            }
            if candidateOffset != nil { break }
        }
        let offset = try XCTUnwrap(candidateOffset)
        XCTAssertEqual(fullMaskPixels[offset + 3], 0)
        XCTAssertTrue((115...140).contains(Int(halfMaskPixels[offset + 3])))
        let unoccludedDifference = colorDistance(
            unoccluded,
            sourcePixels,
            at: offset
        )
        let intermediateDifference = colorDistance(
            intermediate,
            sourcePixels,
            at: offset
        )
        XCTAssertGreaterThan(intermediateDifference, 30)
        XCTAssertLessThan(intermediateDifference, unoccludedDifference)
        XCTAssertLessThan(
            colorDistance(hidden, sourcePixels, at: offset),
            15
        )
    }

    func test拖动预览分层合成与最终图层顺序一致() throws {
        let image = try demonstrationImage()
        let composer = CoverComposer()
        let analysis = try CoverPeopleAnalysis(image: image)
        let below = CoverTextLayer(
            text: "START",
            position: CoverPoint(x: 0.2, y: 0.2),
            fontHeight: 0.07,
            shadowOpacity: 0
        )
        let selected = CoverTextLayer(
            text: "RUNNING",
            position: CoverPoint(x: 0.5, y: 0.56),
            fontHeight: 0.16,
            colorHex: "#FFFF00",
            shadowOpacity: 0,
            depth: .behindAllPeople
        )
        let above = CoverTextLayer(
            text: "FINISH",
            position: CoverPoint(x: 0.5, y: 0.56),
            fontHeight: 0.08,
            shadowOpacity: 0
        )
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let size = extent.size
        let expected = try composer.render(
            image: image,
            layers: [below, selected, above],
            people: analysis
        )
        let stationary = try composer.render(
            image: image,
            layers: [below],
            people: analysis
        )
        let text = try composer.renderTextOverlay(imageSize: size, layer: selected)
        let mask = try XCTUnwrap(composer.visibleTextMask(
            imageSize: size,
            layer: selected,
            people: analysis
        ))
        let following = try XCTUnwrap(composer.renderLayerOverlay(
            imageSize: size,
            layers: [above],
            people: analysis
        ))
        let visibleText = CIImage(cgImage: text)
            .applyingFilter(
                "CISourceInCompositing",
                parameters: [kCIInputBackgroundImageKey: CIImage(cgImage: mask)]
            )
            .cropped(to: extent)
        let composed = CIImage(cgImage: following)
            .composited(over: visibleText.composited(over: CIImage(cgImage: stationary)))
            .cropped(to: extent)
        let actual = try XCTUnwrap(CIContext().createCGImage(composed, from: extent))
        let originalPixels = try pixelBytes(expected)
        let previewPixels = try pixelBytes(actual)
        var significantDifferences = 0
        for offset in stride(from: 0, to: originalPixels.count, by: 4) {
            if colorDistance(originalPixels, previewPixels, at: offset) > 12 {
                significantDifferences += 1
            }
        }
        XCTAssertLessThan(significantDifferences, image.width * image.height / 100)
    }

    func test文字包围盒随字号等比缩放且以位置为中心() {
        let layer = CoverTextLayer(
            text: "RUN",
            position: CoverPoint(x: 0.5, y: 0.4),
            fontHeight: 0.1
        )
        let size = CGSize(width: 1600, height: 900)
        let frame = CoverComposer().textFrame(of: layer, imageSize: size)
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertEqual(frame.midX, 0.5, accuracy: 0.0001)
        var bigger = layer
        bigger.fontHeight = 0.2
        let bigFrame = CoverComposer().textFrame(of: bigger, imageSize: size)
        XCTAssertEqual(bigFrame.width, frame.width * 2, accuracy: 0.0001)
        XCTAssertEqual(bigFrame.height, frame.height * 2, accuracy: 0.0001)
        XCTAssertEqual(bigFrame.midX, 0.5, accuracy: 0.0001)
        var empty = layer
        empty.text = ""
        XCTAssertEqual(
            CoverComposer().textFrame(of: empty, imageSize: size),
            .zero
        )
    }

    func test斜体文字拖到画布中央时按选框中心吸附且可独立脱离轴线() {
        let size = CGSize(width: 1_000, height: 600)
        let layer = CoverTextLayer(
            text: "奔向终点",
            position: CoverPoint(x: 0.34, y: 0.28),
            fontName: "PingFangSC-Regular",
            isItalic: true,
            fontHeight: 0.12,
            rotationDegrees: 28
        )
        let bounds = CoverComposer().textFrame(of: layer, imageSize: size)
        let frame = CGRect(
            x: bounds.minX * size.width - 6,
            y: bounds.minY * size.height - 6,
            width: bounds.width * size.width + 12,
            height: bounds.height * size.height + 12
        )
        let horizontalDelta = size.width / 2 - frame.midX
        let verticalDelta = size.height / 2 - frame.midY

        let centered = CoverTextCenterSnap.resolve(
            from: layer.position,
            frame: frame,
            translation: CGSize(
                width: horizontalDelta + 6,
                height: verticalDelta - 4
            ),
            canvasSize: size
        )
        XCTAssertTrue(centered.horizontal)
        XCTAssertTrue(centered.vertical)
        XCTAssertEqual(
            frame.midX + (centered.position.x - layer.position.x) * size.width,
            size.width / 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            frame.midY + (centered.position.y - layer.position.y) * size.height,
            size.height / 2,
            accuracy: 0.001
        )

        let horizontalOnly = CoverTextCenterSnap.resolve(
            from: layer.position,
            frame: frame,
            translation: CGSize(
                width: horizontalDelta + 3,
                height: verticalDelta + 18
            ),
            canvasSize: size
        )
        XCTAssertTrue(horizontalOnly.horizontal)
        XCTAssertFalse(horizontalOnly.vertical)
        XCTAssertEqual(
            frame.midY + (horizontalOnly.position.y - layer.position.y) * size.height,
            size.height / 2 + 18,
            accuracy: 0.001
        )

        let outside = CoverTextCenterSnap.resolve(
            from: layer.position,
            frame: frame,
            translation: CGSize(
                width: horizontalDelta + 10,
                height: verticalDelta + 10
            ),
            canvasSize: size
        )
        XCTAssertFalse(outside.horizontal)
        XCTAssertFalse(outside.vertical)
        XCTAssertEqual(
            frame.midX + (outside.position.x - layer.position.x) * size.width,
            size.width / 2 + 10,
            accuracy: 0.001
        )
        XCTAssertEqual(
            frame.midY + (outside.position.y - layer.position.y) * size.height,
            size.height / 2 + 10,
            accuracy: 0.001
        )
    }

    func test旋转文字绕自身中心且预览与导出一致() throws {
        let image = try demonstrationImage()
        let composer = CoverComposer()
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let size = extent.size
        let layer = CoverTextLayer(
            text: "RUNNING",
            position: CoverPoint(x: 0.38, y: 0.55),
            fontHeight: 0.16,
            rotationDegrees: 58,
            colorHex: "#FFEA00",
            shadowOpacity: 0
        )
        var horizontal = layer
        horizontal.rotationDegrees = 0
        let plain = try pixelBytes(composer.render(image: image, layers: [horizontal]))
        let exported = try composer.render(image: image, layers: [layer])
        let outputPixels = try pixelBytes(exported)
        XCTAssertNotEqual(outputPixels, plain)
        let overlay = try composer.renderTextOverlay(imageSize: size, layer: layer)
        let composed = try XCTUnwrap(
            CIContext().createCGImage(
                CIImage(cgImage: overlay)
                    .composited(over: CIImage(cgImage: image))
                    .cropped(to: extent),
                from: extent
            )
        )
        let previewPixels = try pixelBytes(composed)
        var differences = 0
        for offset in stride(from: 0, to: outputPixels.count, by: 4) {
            if colorDistance(outputPixels, previewPixels, at: offset) > 12 {
                differences += 1
            }
        }
        XCTAssertLessThan(differences, image.width * image.height / 100)
    }

    func test演示静帧的遮挡封面实际写出PNG和JPEG() throws {
        let image = try demonstrationImage()
        let analysis = try CoverPeopleAnalysis(image: image)
        let subject = try XCTUnwrap(analysis.people.max {
            $0.bounds.width * $0.bounds.height <
                $1.bounds.width * $1.bounds.height
        })
        let layer = CoverTextLayer(
            text: "RUNNING",
            position: CoverPoint(x: 0.5, y: 0.56),
            fontHeight: 0.16,
            colorHex: "#FFF000",
            depth: .behindSelectedPeople,
            selectedPeople: [subject.center]
        )
        let output = try CoverComposer().render(
            image: image,
            layers: [layer],
            people: analysis
        )
        for (fileExtension, expectedType) in [
            ("png", "public.png"),
            ("jpeg", "public.jpeg")
        ] {
            let encoded = try XCTUnwrap(CoverImageEncoding.encode(
                output,
                as: fileExtension
            ))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(
                encoded as CFData,
                nil
            ))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, expectedType)
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(
                source,
                0,
                nil
            ))
            XCTAssertEqual(decoded.width, image.width)
            XCTAssertEqual(decoded.height, image.height)
        }
    }

    private func demonstrationImage() throws -> CGImage {
        let imageURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/RunningFocusVisualQA.png")
        guard FileManager.default.isReadableFile(atPath: imageURL.path),
              let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            throw XCTSkip("当前工作区没有用于人像分割的演示静帧")
        }
        return cgImage
    }

    private func pixelBytes(_ image: CGImage) throws -> [UInt8] {
        let bytesPerRow = image.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        let context = try XCTUnwrap(CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return bytes
    }

    private func colorDistance(
        _ lhs: [UInt8], _ rhs: [UInt8], at offset: Int
    ) -> Int {
        (0..<3).reduce(0) {
            $0 + abs(Int(lhs[offset + $1]) - Int(rhs[offset + $1]))
        }
    }

    private func pixelOffset(_ point: CoverPoint, in image: CGImage) -> Int {
        let x = min(Int(point.x * Double(image.width)), image.width - 1)
        let y = min(Int(point.y * Double(image.height)), image.height - 1)
        return (y * image.width + x) * 4
    }
}
