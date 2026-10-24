import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

public struct CoverPerson: Identifiable, Sendable {
    public let id: Int
    public let center: CoverPoint
    public let bounds: CGRect

    public init(id: Int, center: CoverPoint, bounds: CGRect) {
        self.id = id
        self.center = center
        self.bounds = bounds
    }
}

/// 拖动文字时按实际选框中心吸附画布中心，水平和垂直方向独立吸附。
public struct CoverTextCenterSnap: Equatable, Sendable {
    public let position: CoverPoint
    public let horizontal: Bool
    public let vertical: Bool

    public static func resolve(
        from start: CoverPoint,
        frame: CGRect,
        translation: CGSize,
        canvasSize: CGSize,
        threshold: CGFloat = 9
    ) -> Self {
        guard canvasSize.width > 0, canvasSize.height > 0,
              frame.width > 0, frame.height > 0 else {
            return Self(position: start, horizontal: false, vertical: false)
        }

        let centerX = frame.midX + translation.width
        let centerY = frame.midY + translation.height
        let snapX = abs(centerX - canvasSize.width / 2) <= threshold
        let snapY = abs(centerY - canvasSize.height / 2) <= threshold
        let rawX = start.x + Double(translation.width) / canvasSize.width
        let rawY = start.y + Double(translation.height) / canvasSize.height
        let position = CoverPoint(
            x: min(max(
                rawX + (snapX ? Double(canvasSize.width / 2 - centerX) /
                    canvasSize.width : 0), 0
            ), 1),
            y: min(max(
                rawY + (snapY ? Double(canvasSize.height / 2 - centerY) /
                    canvasSize.height : 0), 0
            ), 1)
        )
        let alignedX = snapX && abs(
            centerX + (position.x - rawX) * canvasSize.width -
                canvasSize.width / 2
        ) < 0.5
        let alignedY = snapY && abs(
            centerY + (position.y - rawY) * canvasSize.height -
                canvasSize.height / 2
        ) < 0.5
        return Self(position: position, horizontal: alignedX, vertical: alignedY)
    }
}

public struct CoverComposer: Sendable {
    /// 共用 CIContext：每次合成新建上下文非常昂贵，是拖动卡顿的主因之一。
    private static let sharedContext = CIContext()

    public init() {}

    public func personID(at point: CoverPoint, in image: CGImage) throws -> Int? {
        try CoverPeopleAnalysis(image: image).id(at: point)
    }

    public func detectPeople(in image: CGImage) throws -> [CoverPerson] {
        let detection = try CoverPeopleAnalysis(image: image)
        return detection.people
    }

    public func render(
        image: CGImage,
        layers: [CoverTextLayer],
        people analysis: CoverPeopleAnalysis? = nil
    ) throws -> CGImage {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let original = CIImage(cgImage: image)
        var result = original
        let behind = layers.contains {
            $0.depth != .front && !$0.text.isEmpty && $0.occlusionStrength > 0
        }
        let masks = behind ? try (analysis ?? CoverPeopleAnalysis(image: image)) : nil
        for layer in layers where !layer.text.isEmpty {
            let text = try renderText(layer, in: extent)
            if layer.depth == .front || layer.occlusionStrength <= 0 {
                result = text.composited(over: result).cropped(to: extent)
                continue
            }
            guard let masks else {
                result = text.composited(over: result).cropped(to: extent)
                continue
            }
            let selectedIDs: IndexSet
            switch layer.depth {
            case .front:
                continue
            case .behindAllPeople:
                selectedIDs = masks.allIDs
            case .behindSelectedPeople:
                selectedIDs = masks.ids(at: layer.selectedPeople)
            }
            if let mask = try masks.scaledMask(
                for: selectedIDs,
                targetSize: extent.size,
                strength: layer.occlusionStrength
            ) {
                // 文字「减去」人像区域：蒙版内 alpha 为 1，文字在人像处完全消失
                let visibleText = text.applyingFilter(
                    "CISourceOutCompositing",
                    parameters: [kCIInputBackgroundImageKey: mask]
                ).cropped(to: extent)
                result = visibleText.composited(over: result).cropped(to: extent)
            } else {
                result = text.composited(over: result).cropped(to: extent)
            }
        }
        guard let output = Self.sharedContext.createCGImage(result, from: extent) else {
            throw VideoFrameSnapshotError.imageCreationFailed
        }
        return output
    }

    /// 将单个文字图层预渲染为透明图片，拖动时只做视图变换，不重新合成整张封面。
    public func renderTextOverlay(
        imageSize: CGSize,
        layer: CoverTextLayer
    ) throws -> CGImage {
        let extent = CGRect(origin: .zero, size: imageSize)
        guard let output = Self.sharedContext.createCGImage(
            try renderText(layer, in: extent),
            from: extent
        ) else {
            throw VideoFrameSnapshotError.imageCreationFailed
        }
        return output
    }

    /// 将位于选中文字上方的其他图层单独合成，保持拖动时的图层顺序。
    public func renderLayerOverlay(
        imageSize: CGSize,
        layers: [CoverTextLayer],
        people: CoverPeopleAnalysis?
    ) throws -> CGImage? {
        guard !layers.isEmpty else { return nil }
        let extent = CGRect(origin: .zero, size: imageSize)
        guard let transparent = Self.sharedContext.createCGImage(
            CIImage(color: .clear).cropped(to: extent),
            from: extent
        ) else {
            throw VideoFrameSnapshotError.imageCreationFailed
        }
        return try render(image: transparent, layers: layers, people: people)
    }

    /// 人物遮挡蒙版相对画布固定，文字平移时不会把「挖空」的区域一起带走。
    public func visibleTextMask(
        imageSize: CGSize,
        layer: CoverTextLayer,
        people: CoverPeopleAnalysis?
    ) throws -> CGImage? {
        guard layer.depth != .front,
              layer.occlusionStrength > 0,
              let people else { return nil }
        let ids: IndexSet
        switch layer.depth {
        case .front:
            return nil
        case .behindAllPeople:
            ids = people.allIDs
        case .behindSelectedPeople:
            ids = people.ids(at: layer.selectedPeople)
        }
        guard let personMask = try people.scaledMask(
            for: ids,
            targetSize: imageSize,
            strength: layer.occlusionStrength
        ) else { return nil }
        let extent = CGRect(origin: .zero, size: imageSize)
        let inverse = CIImage(color: .white)
            .cropped(to: extent)
            .applyingFilter(
                "CISourceOutCompositing",
                parameters: [kCIInputBackgroundImageKey: personMask]
            )
            .cropped(to: extent)
        guard let image = Self.sharedContext.createCGImage(inverse, from: extent) else {
            throw VideoFrameSnapshotError.imageCreationFailed
        }
        return image
    }

    /// 归一化坐标（左上原点）下的文字包围盒，供编辑器绘制选中框与拖拽缩放。
    public func textFrame(of layer: CoverTextLayer, imageSize: CGSize) -> CGRect {
        guard !layer.text.isEmpty, layer.fontHeight > 0,
              imageSize.width > 1, imageSize.height > 1 else { return .zero }
        let font = Self.font(for: layer, size: 1)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: layer.text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font
            ]
        ))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let unitWidth = CGFloat(CTLineGetTypographicBounds(
            line, &ascent, &descent, &leading
        ))
        let aspect = imageSize.height / imageSize.width
        let syntheticSlant = layer.isItalic &&
            !CTFontGetSymbolicTraits(font).contains(.traitItalic)
        let italicOverhang = syntheticSlant ? (ascent + descent) * 0.21 : 0
        // 拖拽中心必须与实际绘制中心一致；斜体额外占宽只向右扩展。
        let width = (unitWidth + italicOverhang) * layer.fontHeight * aspect
        let height = (ascent + descent) * layer.fontHeight
        let top = layer.position.y + layer.fontHeight * 0.32 - ascent * layer.fontHeight
        return CGRect(
            x: layer.position.x -
                (unitWidth * layer.fontHeight * aspect) / 2,
            y: top,
            width: width,
            height: height
        )
    }

    private func renderText(
        _ layer: CoverTextLayer,
        in extent: CGRect
    ) throws -> CIImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(extent.width),
            height: Int(extent.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw VideoFrameSnapshotError.imageCreationFailed
        }
        let fontSize = max(6, layer.fontHeight * extent.height)
        let font = Self.font(for: layer, size: fontSize)
        let visibleColor = color(layer.colorHex)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: layer.text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    visibleColor
            ]
        ))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let x = extent.minX + layer.position.x * extent.width - width / 2
        let y = extent.maxY - layer.position.y * extent.height - fontSize * 0.32
        let fontTraits = CTFontGetSymbolicTraits(font)
        let syntheticItalic = layer.isItalic && !fontTraits.contains(.traitItalic)
        let syntheticBold = layer.isBold && !fontTraits.contains(.traitBold)
        if layer.rotationDegrees.isFinite && layer.rotationDegrees != 0 {
            let center = CGPoint(
                x: extent.minX + layer.position.x * extent.width,
                y: y + (ascent - descent) / 2
            )
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: -layer.rotationDegrees * .pi / 180)
            context.translateBy(x: -center.x, y: -center.y)
        }
        if syntheticItalic {
            // textPosition 不会自动补偿 textMatrix 的斜切位移；
            // 以排版框中心为锚点修正，避免斜体文字越出编辑框。
            context.textMatrix = CGAffineTransform(
                a: 1, b: 0, c: 0.21, d: 1,
                tx: -0.21 * (y + (ascent - descent) / 2),
                ty: 0
            )
        }
        context.textPosition = CGPoint(x: x, y: y)
        if layer.shadowOpacity > 0 {
            context.setShadow(
                offset: CGSize(width: 0, height: -max(1, fontSize * 0.04)),
                blur: max(1, fontSize * 0.08),
                color: CGColor(
                    red: 0, green: 0, blue: 0,
                    alpha: min(max(layer.shadowOpacity, 0), 1)
                )
            )
        }
        if layer.strokeWidth > 0 {
            context.saveGState()
            context.setLineJoin(.round)
            context.setTextDrawingMode(.stroke)
            context.setLineWidth(max(0.5, fontSize * layer.strokeWidth))
            let strokeLine = CTLineCreateWithAttributedString(NSAttributedString(
                string: layer.text,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                        color(layer.strokeHex)
                ]
            ))
            CTLineDraw(strokeLine, context)
            context.restoreGState()
            context.textPosition = CGPoint(x: x, y: y)
        }
        if syntheticBold {
            context.setTextDrawingMode(.fillStroke)
            context.setLineWidth(max(0.8, fontSize * 0.026))
            context.setStrokeColor(visibleColor)
        }
        CTLineDraw(line, context)
        guard let rendered = context.makeImage() else {
            throw VideoFrameSnapshotError.imageCreationFailed
        }
        return CIImage(cgImage: rendered)
    }

    /// 优先选择相同字体家族的真实粗体和斜体字面；缺少变体时在绘制中合成。
    public static func font(for layer: CoverTextLayer, size: CGFloat) -> CTFont {
        let base = CTFontCreateWithName(layer.fontName as CFString, size, nil)
        var desired: CTFontSymbolicTraits = []
        if layer.isBold { desired.insert(.traitBold) }
        if layer.isItalic { desired.insert(.traitItalic) }
        let requested: CTFontSymbolicTraits = [.traitBold, .traitItalic]
        if let matched = CTFontCreateCopyWithSymbolicTraits(
            base, size, nil, desired, requested
        ) {
            return matched
        }
        if layer.isBold,
           let bold = CTFontCreateCopyWithSymbolicTraits(
               base, size, nil, .traitBold, .traitBold
           ) {
            return bold
        }
        if layer.isItalic,
           let italic = CTFontCreateCopyWithSymbolicTraits(
               base, size, nil, .traitItalic, .traitItalic
           ) {
            return italic
        }
        return base
    }

    private func color(_ hex: String) -> CGColor {
        let normalized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(normalized, radix: 16) ?? 0xFFFFFF
        return CGColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

public enum CoverImageEncoding {
    public static func encode(
        _ image: CGImage,
        as fileExtension: String
    ) -> Data? {
        let normalized = fileExtension.lowercased()
        let type = normalized == "jpg" || normalized == "jpeg"
            ? UTType.jpeg.identifier : UTType.png.identifier
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            type as CFString,
            1,
            nil
        ) else { return nil }
        let options: [CFString: Any] = normalized == "jpg" || normalized == "jpeg"
            ? [kCGImageDestinationLossyCompressionQuality: 0.9] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// 检测结果仅针对创建时传入的图片；编辑预览和点击选人共用一次 Vision 分割。
/// 统一读取 Vision 蒙版像素：不同系统/接口下蒙版可能是 8 位整数、
/// 32 位浮点或 BGRA 字节，读错格式会出现噪点与半透明遮挡。
private struct MaskReader {
    let base: UnsafeMutableRawPointer
    let stride: Int
    let width: Int
    let height: Int
    let kind: Kind

    enum Kind {
        case mono8
        case float32
        case bgra8
    }

    init(buffer: CVPixelBuffer, base: UnsafeMutableRawPointer) {
        self.base = base
        stride = CVPixelBufferGetBytesPerRow(buffer)
        width = CVPixelBufferGetWidth(buffer)
        height = CVPixelBufferGetHeight(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        if format == kCVPixelFormatType_OneComponent8 {
            kind = .mono8
        } else if format == kCVPixelFormatType_32BGRA {
            kind = .bgra8
        } else {
            kind = .float32
        }
    }

    /// 将 Vision 的覆盖强度转换为 alpha，强化人物内部、保留边缘过渡。
    func alphaByte(x: Int, y: Int) -> UInt8 {
        let raw = value(x: x, y: y)
        switch kind {
        case .float32:
            let coverage = min(max(raw, 0), 1)
            let solidCoverage = min(coverage / 0.8, 1)
            return UInt8((solidCoverage * 255).rounded())
        case .mono8, .bgra8:
            return UInt8(min(max(raw, 0), 255))
        }
    }

    /// 返回原始值：实例蒙版里是人物编号（1、2、3…），
    /// 缩放蒙版里是 0…1 或 0…255 的覆盖强度，由调用方按语义处理。
    func value(x: Int, y: Int) -> Double {
        switch kind {
        case .mono8:
            let byte = base.load(fromByteOffset: y * stride + x, as: UInt8.self)
            return Double(byte)
        case .float32:
            let bits = base.load(fromByteOffset: y * stride + x * 4, as: UInt32.self)
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : 0
        case .bgra8:
            let offset = y * stride + x * 4
            let b = Double(base.load(fromByteOffset: offset, as: UInt8.self))
            let g = Double(base.load(fromByteOffset: offset + 1, as: UInt8.self))
            let r = Double(base.load(fromByteOffset: offset + 2, as: UInt8.self))
            let a = Double(base.load(fromByteOffset: offset + 3, as: UInt8.self))
            let rgb = max(b, max(g, r))
            return rgb > 0 ? rgb : a
        }
    }
}

public final class CoverPeopleAnalysis: @unchecked Sendable {
    public let people: [CoverPerson]
    fileprivate let allIDs: IndexSet
    private let observation: VNInstanceMaskObservation?
    private let handler: VNImageRequestHandler
    private let width: Int
    private let height: Int
    private let renderLock = NSLock()

    public init(image: CGImage) throws {
        width = image.width
        height = image.height
        handler = VNImageRequestHandler(cgImage: image)
        let request = VNGeneratePersonInstanceMaskRequest()
        try handler.perform([request])
        observation = request.results?.first
        allIDs = observation?.allInstances ?? []
        guard let observation else {
            people = []
            return
        }
        let knownIDs = observation.allInstances
        people = Self.scanPeople(observation: observation, knownIDs: knownIDs)
    }

    private static func scanPeople(
        observation: VNInstanceMaskObservation,
        knownIDs: IndexSet
    ) -> [CoverPerson] {
        let mask = observation.instanceMask
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return [] }
        let reader = MaskReader(buffer: mask, base: base)
        let maskWidth = reader.width
        let maskHeight = reader.height
        guard maskWidth > 0, maskHeight > 0 else { return [] }
        var ids = [Int](repeating: 0, count: maskWidth * maskHeight)
        for y in 0..<maskHeight {
            for x in 0..<maskWidth {
                ids[y * maskWidth + x] = Int(reader.value(x: x, y: y).rounded())
            }
        }
        // 实例蒙版偶有噪点行/噪点列：按连通域分析，丢弃面积过小
        // 或形状像一条线（宽高比极端）的连通域，再合并成人物框。
        var visited = [Bool](repeating: false, count: ids.count)
        var bounds: [Int: (Int, Int, Int, Int)] = [:]
        var stack: [Int] = []
        for start in ids.indices where ids[start] != 0 && !visited[start] {
            let id = ids[start]
            stack.append(start)
            visited[start] = true
            var size = 0
            var minX = maskWidth, minY = maskHeight, maxX = 0, maxY = 0
            while let index = stack.popLast() {
                let x = index % maskWidth
                let y = index / maskWidth
                size += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                let neighbours = [
                    x > 0 ? index - 1 : nil,
                    x < maskWidth - 1 ? index + 1 : nil,
                    y > 0 ? index - maskWidth : nil,
                    y < maskHeight - 1 ? index + maskWidth : nil
                ]
                for next in neighbours.compactMap({ $0 })
                where !visited[next] && ids[next] == id {
                    visited[next] = true
                    stack.append(next)
                }
            }
            let componentWidth = maxX - minX + 1
            let componentHeight = maxY - minY + 1
            let lineLike = componentWidth > componentHeight * 6 ||
                componentHeight > componentWidth * 6
            guard size >= 600, !lineLike else { continue }
            let old = bounds[id] ?? (minX, minY, maxX, maxY)
            bounds[id] = (
                min(old.0, minX), min(old.1, minY),
                max(old.2, maxX), max(old.3, maxY)
            )
        }
        return bounds.compactMap { id, box -> CoverPerson? in
            guard knownIDs.contains(id) else { return nil }
            let rect = CGRect(
                x: CGFloat(box.0) / CGFloat(maskWidth),
                y: CGFloat(box.1) / CGFloat(maskHeight),
                width: CGFloat(box.2 - box.0 + 1) / CGFloat(maskWidth),
                height: CGFloat(box.3 - box.1 + 1) / CGFloat(maskHeight)
            )
            return CoverPerson(
                id: id,
                center: CoverPoint(x: rect.midX, y: rect.midY),
                bounds: rect
            )
        }.sorted { $0.id < $1.id }
    }

    func ids(at points: [CoverPoint]) -> IndexSet {
        var selected = IndexSet()
        for point in points {
            if let id = id(at: point) {
                selected.insert(id)
            }
        }
        return selected
    }

    public func id(at point: CoverPoint) -> Int? {
        guard let observation,
              (0...1).contains(point.x),
              (0...1).contains(point.y) else { return nil }
        let mask = observation.instanceMask
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let x = min(max(Int(point.x * Double(width)), 0), width - 1)
        let y = min(max(Int(point.y * Double(height)), 0), height - 1)
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let reader = MaskReader(buffer: mask, base: base)
        let id = Int(reader.value(x: x, y: y).rounded())
        return allIDs.contains(id) ? id : nil
    }

    /// 蒙版按目标渲染尺寸缩放，检测图与渲染图分辨率可以不同。
    /// 蒙版按目标渲染尺寸缩放，检测图与渲染图分辨率可以不同。
    /// 调试：导出指定实例的原始缩放蒙版字节统计与图片。
    public func debugMaskInfo(for id: Int, targetSize: CGSize) -> (String, CIImage?) {
        guard let observation else { return ("no observation", nil) }
        do {
            let buffer = try observation.generateScaledMaskForImage(
                forInstances: IndexSet(integer: id),
                from: handler
            )
            let w = CVPixelBufferGetWidth(buffer)
            let h = CVPixelBufferGetHeight(buffer)
            let format = CVPixelBufferGetPixelFormatType(buffer)
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buffer) else {
                return ("no base", nil)
            }
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            var samples: [UInt8] = []
            for i in 0..<16 {
                samples.append(base.load(fromByteOffset: i, as: UInt8.self))
            }
            var mid: [UInt8] = []
            let midOffset = (h / 2) * stride + (w / 2) * 4
            for i in 0..<16 {
                mid.append(base.load(fromByteOffset: midOffset + i, as: UInt8.self))
            }
            let reader = MaskReader(buffer: buffer, base: base)
            var rows: [String] = []
            for gy in 0..<12 {
                var line = ""
                for gx in 0..<24 {
                    let x = gx * w / 24
                    let y = gy * h / 12
                    let v = reader.value(x: x, y: y)
                    line += v <= 0.01 ? "." : (v >= 0.99 ? "#" : "+")
                }
                rows.append(line)
            }
            var peak: Double = 0
            var histogram: [Double: Int] = [:]
            for y in 0..<h {
                for x in 0..<w {
                    let v = reader.value(x: x, y: y)
                    peak = max(peak, v)
                    let key = (v * 20).rounded() / 20
                    histogram[key, default: 0] += 1
                }
            }
            rows.append("hist=\(histogram.sorted { $0.key < $1.key }.suffix(10))")
            var instanceRows: [String] = []
            instanceRows.append("scaledKindDebug=\(CVPixelBufferGetPixelFormatType(buffer))")
            let instanceMask = observation.instanceMask
            CVPixelBufferLockBaseAddress(instanceMask, .readOnly)
            if let instanceBase = CVPixelBufferGetBaseAddress(instanceMask) {
                let instanceReader = MaskReader(
                    buffer: instanceMask,
                    base: instanceBase
                )
                let iw = instanceReader.width
                let ih = instanceReader.height
                for gy in 0..<12 {
                    var line = ""
                    for gx in 0..<24 {
                        let v = instanceReader.value(x: gx * iw / 24, y: gy * ih / 12)
                        let id = Int(v.rounded())
                        line += id == 0 ? "." : String(id % 10)
                    }
                    instanceRows.append(line)
                }
                var histogram: [Int: Int] = [:]
                for y in 0..<ih {
                    for x in 0..<iw {
                        let id = Int(instanceReader.value(x: x, y: y).rounded())
                        histogram[id, default: 0] += 1
                    }
                }
                instanceRows.append("hist=\(histogram.sorted { $0.key < $1.key })")
                instanceRows.append("instanceFormat=\(CVPixelBufferGetPixelFormatType(instanceMask))")
            }
            CVPixelBufferUnlockBaseAddress(instanceMask, .readOnly)
            let info = "format=\(format) w=\(w) h=\(h) stride=\(stride) peak=\(peak) mono8=\(kCVPixelFormatType_OneComponent8) f32=\(kCVPixelFormatType_OneComponent32Float) bgra=\(kCVPixelFormatType_32BGRA) half=\(kCVPixelFormatType_OneComponent16Half)\n" + rows.joined(separator: "\n") + "\nINSTANCE:\n" + instanceRows.joined(separator: "\n")
            let ci = CIImage(cvPixelBuffer: buffer)
            return (info, ci)
        } catch {
            return ("error \(error)", nil)
        }
    }

    fileprivate func scaledMask(
        for ids: IndexSet,
        targetSize: CGSize,
        strength: Double
    ) throws -> CIImage? {
        guard let observation, !ids.isEmpty,
              strength > 0 else { return nil }
        let clampedStrength = min(max(strength, 0), 1)
        renderLock.lock()
        defer { renderLock.unlock() }
        let buffer = try observation.generateScaledMaskForImage(
            forInstances: ids,
            from: handler
        )
        let maskWidth = CVPixelBufferGetWidth(buffer)
        let maskHeight = CVPixelBufferGetHeight(buffer)
        guard maskWidth > 0, maskHeight > 0 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let reader = MaskReader(buffer: buffer, base: base)
        var rgba = [UInt8](repeating: 0, count: maskWidth * maskHeight * 4)
        var maxAlpha: UInt8 = 0
        for y in 0..<maskHeight {
            for x in 0..<maskWidth {
                let alpha = UInt8(
                    (Double(reader.alphaByte(x: x, y: y)) * clampedStrength)
                        .rounded()
                )
                rgba[(y * maskWidth + x) * 4 + 3] = alpha
                maxAlpha = max(maxAlpha, alpha)
            }
        }
        guard maxAlpha > 0 else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &rgba,
                width: maskWidth,
                height: maskHeight,
                bitsPerComponent: 8,
                bytesPerRow: maskWidth * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let maskImage = context.makeImage() else { return nil }
        let scale = CGAffineTransform(
            scaleX: targetSize.width / CGFloat(maskWidth),
            y: targetSize.height / CGFloat(maskHeight)
        )
        return CIImage(cgImage: maskImage)
            .transformed(by: scale)
            .cropped(to: CGRect(
                x: 0,
                y: 0,
                width: targetSize.width,
                height: targetSize.height
            ))
    }

}
