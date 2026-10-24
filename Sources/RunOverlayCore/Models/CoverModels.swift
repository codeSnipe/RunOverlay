import CoreText
import Foundation

public struct CoverPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct CoverImageResource: Codable, Hashable, Sendable {
    public var fileURL: URL
    public var bookmarkData: Data?
    public var resourceRelativePath: String?

    public init(
        fileURL: URL,
        bookmarkData: Data? = nil,
        resourceRelativePath: String? = nil
    ) {
        self.fileURL = fileURL
        self.bookmarkData = bookmarkData
        self.resourceRelativePath = resourceRelativePath
    }
}

public struct CoverVideoFrame: Codable, Hashable, Sendable {
    public var seconds: TimeInterval
    public var includesDataLayer: Bool
    public var aspectRatio: ExportAspectRatio
    public var maximumHeight: Int
    public var rotation: VideoRotation

    public init(
        seconds: TimeInterval,
        includesDataLayer: Bool = false,
        aspectRatio: ExportAspectRatio = .source,
        maximumHeight: Int = 1_080,
        rotation: VideoRotation = .none
    ) {
        self.seconds = seconds
        self.includesDataLayer = includesDataLayer
        self.aspectRatio = aspectRatio
        self.maximumHeight = maximumHeight
        self.rotation = rotation
    }
}

public enum CoverSource: Codable, Hashable, Sendable {
    case videoFrame(CoverVideoFrame)
    case image(CoverImageResource)
}

public enum CoverTextDepth: String, Codable, Hashable, Sendable {
    case front
    case behindAllPeople
    case behindSelectedPeople
}

public struct CoverTextColorPreset: Identifiable, Hashable, Sendable {
    public static let defaultStrokeWidth = 0.035

    public let id: Int
    public let textHex: String
    public let strokeHex: String

    public init(id: Int, textHex: String, strokeHex: String) {
        self.id = id
        self.textHex = textHex
        self.strokeHex = strokeHex
    }

    /// 预览与应用共用描边规则；手动设置的细描边不应被预览放大。
    public func strokeWidth(afterApplyingTo current: Double) -> Double {
        current > 0 ? current : Self.defaultStrokeWidth
    }

    /// 双颜色预设，优先保证封面文字在明暗背景上都有足够区分度。
    public static let recommendations: [CoverTextColorPreset] = [
        .init(id: 1, textHex: "#FFFFFF", strokeHex: "#101820"),
        .init(id: 2, textHex: "#D7FF3F", strokeHex: "#14200F"),
        .init(id: 3, textHex: "#55E6FF", strokeHex: "#0D2940"),
        .init(id: 4, textHex: "#FF654F", strokeHex: "#301516"),
        .init(id: 5, textHex: "#FFAD72", strokeHex: "#392016"),
        .init(id: 6, textHex: "#EFD77E", strokeHex: "#31251B"),
        .init(id: 7, textHex: "#B9D99B", strokeHex: "#183326"),
        .init(id: 8, textHex: "#88D9C0", strokeHex: "#153735"),
        .init(id: 9, textHex: "#182742", strokeHex: "#F7F2E6"),
        .init(id: 10, textHex: "#D7B8FF", strokeHex: "#2D2044")
    ]
}

public struct CoverTextLayer: Identifiable, Codable, Hashable, Sendable {
    /// 文字可占据大部分封面高度，滑块与画布缩放共用同一范围。
    public static let fontHeightRange: ClosedRange<Double> = 0.02...0.8

    public var id: UUID
    public var text: String
    public var position: CoverPoint
    public var fontName: String
    public var isBold: Bool
    public var isItalic: Bool
    /// 字号相对于整幅图片的高度，保证不同导出分辨率下排版一致。
    public var fontHeight: Double
    /// 顺时针旋转角度，绕文字可见区域的中心旋转。
    public var rotationDegrees: Double
    public var colorHex: String
    public var strokeHex: String
    public var strokeWidth: Double
    public var shadowOpacity: Double
    public var depth: CoverTextDepth
    /// 人像遮挡强度，0 为文字完全显示，1 为人像内文字完全隐藏。
    public var occlusionStrength: Double
    /// 用归一化坐标记录目标人物位置，不依赖 Vision 每次运行的临时实例编号。
    public var selectedPeople: [CoverPoint]

    public init(
        id: UUID = UUID(),
        text: String = "",
        position: CoverPoint = CoverPoint(x: 0.5, y: 0.5),
        fontName: String = "HelveticaNeue-Bold",
        isBold: Bool? = nil,
        isItalic: Bool? = nil,
        fontHeight: Double = 0.08,
        rotationDegrees: Double = 0,
        colorHex: String = "#FFFFFF",
        strokeHex: String = "#000000",
        strokeWidth: Double = 0,
        shadowOpacity: Double = 0.55,
        depth: CoverTextDepth = .front,
        occlusionStrength: Double = 1,
        selectedPeople: [CoverPoint] = []
    ) {
        self.id = id
        self.text = text
        self.position = position
        self.fontName = fontName
        let traits = Self.intrinsicFontTraits(for: fontName)
        self.isBold = isBold ?? traits.contains(.traitBold)
        self.isItalic = isItalic ?? traits.contains(.traitItalic)
        self.fontHeight = fontHeight
        self.rotationDegrees = rotationDegrees
        self.colorHex = colorHex
        self.strokeHex = strokeHex
        self.strokeWidth = strokeWidth
        self.shadowOpacity = shadowOpacity
        self.depth = depth
        self.occlusionStrength = occlusionStrength
        self.selectedPeople = selectedPeople
    }

    public mutating func apply(_ preset: CoverTextColorPreset) {
        colorHex = preset.textHex
        strokeHex = preset.strokeHex
        strokeWidth = preset.strokeWidth(afterApplyingTo: strokeWidth)
    }

    private static func intrinsicFontTraits(for fontName: String) -> CTFontSymbolicTraits {
        let font = CTFontCreateWithName(fontName as CFString, 12, nil)
        return CTFontGetSymbolicTraits(font)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, position, fontName, isBold, isItalic
        case fontHeight, rotationDegrees, colorHex, strokeHex
        case strokeWidth, shadowOpacity, depth, occlusionStrength, selectedPeople
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        position = try container.decode(CoverPoint.self, forKey: .position)
        fontName = try container.decode(String.self, forKey: .fontName)
        let traits = Self.intrinsicFontTraits(for: fontName)
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold)
            ?? traits.contains(.traitBold)
        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic)
            ?? traits.contains(.traitItalic)
        fontHeight = try container.decode(Double.self, forKey: .fontHeight)
        rotationDegrees = try container.decodeIfPresent(
            Double.self,
            forKey: .rotationDegrees
        ) ?? 0
        colorHex = try container.decode(String.self, forKey: .colorHex)
        strokeHex = try container.decode(String.self, forKey: .strokeHex)
        strokeWidth = try container.decode(Double.self, forKey: .strokeWidth)
        shadowOpacity = try container.decode(Double.self, forKey: .shadowOpacity)
        depth = try container.decode(CoverTextDepth.self, forKey: .depth)
        occlusionStrength = try container.decodeIfPresent(
            Double.self,
            forKey: .occlusionStrength
        ) ?? 1
        selectedPeople = try container.decode([CoverPoint].self, forKey: .selectedPeople)
    }
}

public struct VideoCover: Codable, Hashable, Sendable {
    public var source: CoverSource
    public var textLayers: [CoverTextLayer]
    public var exportedImage: CoverImageResource?

    public init(
        source: CoverSource,
        textLayers: [CoverTextLayer] = [],
        exportedImage: CoverImageResource? = nil
    ) {
        self.source = source
        self.textLayers = textLayers
        self.exportedImage = exportedImage
    }

    /// 复制完整的文字样式与人物遮挡设置，错开放置在原图层上方。
    @discardableResult
    public mutating func duplicateTextLayer(id: UUID) -> CoverTextLayer? {
        guard let index = textLayers.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        var duplicate = textLayers[index]
        duplicate.id = UUID()
        duplicate.position = CoverPoint(
            x: Self.offsetCoordinate(duplicate.position.x),
            y: Self.offsetCoordinate(duplicate.position.y)
        )
        textLayers.insert(duplicate, at: index + 1)
        exportedImage = nil
        return duplicate
    }

    private static func offsetCoordinate(_ coordinate: Double) -> Double {
        let offset = coordinate > 0.85 ? -0.035 : 0.035
        return min(max(coordinate + offset, 0), 1)
    }

    /// 再次打开视频帧封面时使用当前播放帧，同时保留文字编辑；导入图片不受影响。
    @discardableResult
    public mutating func refreshVideoFrame(_ frame: CoverVideoFrame) -> Bool {
        guard case let .videoFrame(previous) = source, previous != frame else {
            return false
        }
        source = .videoFrame(frame)
        exportedImage = nil
        for index in textLayers.indices {
            textLayers[index].selectedPeople.removeAll()
        }
        return true
    }
}
