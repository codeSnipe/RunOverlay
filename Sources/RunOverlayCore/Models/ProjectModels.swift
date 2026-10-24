import Foundation

public enum UnitSystem: String, Codable, Hashable, Sendable {
    case automatic
    case metric
    case imperial
}

public enum VideoTextLanguage: String, CaseIterable, Codable, Hashable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"
}

public enum SmoothingLevel: String, Codable, Hashable, Sendable {
    case off
    case light
    case standard
    case strong

    public var displayName: String {
        switch self {
        case .off: RunOverlayLocalization.text("smoothing.off")
        case .light: RunOverlayLocalization.text("smoothing.light")
        case .standard: RunOverlayLocalization.text("smoothing.standard")
        case .strong: RunOverlayLocalization.text("smoothing.strong")
        }
    }
}

public enum ExportAspectRatio: String, CaseIterable, Codable, Hashable, Sendable {
    case source
    case landscape16x9
    case portrait9x16
    case square
    case portrait4x5
    case landscape4x3
    case portrait3x4

    public var displayName: String {
        switch self {
        case .source: RunOverlayLocalization.text("aspect.source")
        case .landscape16x9: RunOverlayLocalization.text("aspect.landscape16x9")
        case .portrait9x16: RunOverlayLocalization.text("aspect.portrait9x16")
        case .square: RunOverlayLocalization.text("aspect.square")
        case .portrait4x5: RunOverlayLocalization.text("aspect.portrait4x5")
        case .landscape4x3: RunOverlayLocalization.text("aspect.landscape4x3")
        case .portrait3x4: RunOverlayLocalization.text("aspect.portrait3x4")
        }
    }

    public var widthOverHeight: Double? {
        switch self {
        case .source: nil
        case .landscape16x9: 16.0 / 9.0
        case .portrait9x16: 9.0 / 16.0
        case .square: 1
        case .portrait4x5: 4.0 / 5.0
        case .landscape4x3: 4.0 / 3.0
        case .portrait3x4: 3.0 / 4.0
        }
    }

    public func outputDimensions(
        source: PixelDimensions,
        shortEdge: Int = 1_080
    ) -> PixelDimensions {
        let sourceWidth = max(source.width, 1)
        let sourceHeight = max(source.height, 1)
        let aspect = widthOverHeight ??
            Double(sourceWidth) / Double(sourceHeight)
        let shortSide = max(shortEdge, 2)
        let width: Double
        let height: Double

        if aspect >= 1 {
            height = Double(shortSide)
            width = height * aspect
        } else {
            width = Double(shortSide)
            height = width / aspect
        }

        return PixelDimensions(
            width: Self.evenDimension(width),
            height: Self.evenDimension(height)
        )
    }

    private static func evenDimension(_ value: Double) -> Int {
        max(2, Int((value / 2).rounded()) * 2)
    }
}

public struct ExportSettings: Codable, Hashable, Sendable {
    public enum Codec: String, Codable, Hashable, Sendable {
        case h264
        case hevc

        public var displayName: String {
            switch self {
            case .h264: RunOverlayLocalization.text("codec.h264")
            case .hevc: RunOverlayLocalization.text("codec.hevc")
            }
        }

        public var fileExtension: String {
            switch self {
            case .h264: "mp4"
            case .hevc: "mov"
            }
        }
    }

    public var codec: Codec
    public var maximumHeight: Int
    public var parallelTaskCount: Int
    public var preservesAudio: Bool
    public var aspectRatio: ExportAspectRatio
    public var videoTextLanguage: VideoTextLanguage

    public init(
        codec: Codec = .h264,
        maximumHeight: Int = 1080,
        parallelTaskCount: Int = 1,
        preservesAudio: Bool = true,
        aspectRatio: ExportAspectRatio = .landscape16x9,
        videoTextLanguage: VideoTextLanguage = .chinese
    ) {
        self.codec = codec
        self.maximumHeight = maximumHeight
        self.parallelTaskCount = parallelTaskCount
        self.preservesAudio = preservesAudio
        self.aspectRatio = aspectRatio
        self.videoTextLanguage = videoTextLanguage
    }

    private enum CodingKeys: String, CodingKey {
        case codec
        case maximumHeight
        case parallelTaskCount
        case preservesAudio
        case aspectRatio
        case videoTextLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        codec = try container.decode(Codec.self, forKey: .codec)
        maximumHeight = try container.decode(Int.self, forKey: .maximumHeight)
        parallelTaskCount = try container.decode(
            Int.self,
            forKey: .parallelTaskCount
        )
        preservesAudio = try container.decode(Bool.self, forKey: .preservesAudio)
        aspectRatio = try container.decodeIfPresent(
            ExportAspectRatio.self,
            forKey: .aspectRatio
        ) ?? .source
        videoTextLanguage = try container.decodeIfPresent(
            VideoTextLanguage.self,
            forKey: .videoTextLanguage
        ) ?? .chinese
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(codec, forKey: .codec)
        try container.encode(maximumHeight, forKey: .maximumHeight)
        try container.encode(parallelTaskCount, forKey: .parallelTaskCount)
        try container.encode(preservesAudio, forKey: .preservesAudio)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encode(videoTextLanguage, forKey: .videoTextLanguage)
    }
}

public struct RunOverlayProject: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static var defaultName: String {
        RunOverlayLocalization.text("project.untitled")
    }

    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var activitySource: ActivitySource?
    public var activitySamples: [ActivitySample]
    public var videos: [VideoItem]
    public var overlay: OverlayConfiguration
    public var unitSystem: UnitSystem
    public var smoothingLevel: SmoothingLevel
    public var exportSettings: ExportSettings

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: UUID = UUID(),
        name: String = RunOverlayProject.defaultName,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        activitySource: ActivitySource? = nil,
        activitySamples: [ActivitySample] = [],
        videos: [VideoItem] = [],
        overlay: OverlayConfiguration = .preset(.runningFocus),
        unitSystem: UnitSystem = .automatic,
        smoothingLevel: SmoothingLevel = .standard,
        exportSettings: ExportSettings = ExportSettings()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activitySource = activitySource
        self.activitySamples = activitySamples
        self.videos = videos
        self.overlay = overlay
        self.unitSystem = unitSystem
        self.smoothingLevel = smoothingLevel
        self.exportSettings = exportSettings
    }

    /// 只清除当前项目中的运动数据，不更改视频和磁盘上的原始文件。
    public mutating func clearActivity() {
        activitySource = nil
        activitySamples.removeAll()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case name
        case createdAt
        case updatedAt
        case activitySource
        case activitySamples
        case videos
        case overlay
        case unitSystem
        case smoothingLevel
        case exportSettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        activitySource = try container.decodeIfPresent(
            ActivitySource.self,
            forKey: .activitySource
        )
        activitySamples = try container.decodeIfPresent(
            [ActivitySample].self,
            forKey: .activitySamples
        ) ?? []
        videos = try container.decode([VideoItem].self, forKey: .videos)
        overlay = try container.decode(OverlayConfiguration.self, forKey: .overlay)
        unitSystem = try container.decode(UnitSystem.self, forKey: .unitSystem)
        smoothingLevel = try container.decode(
            SmoothingLevel.self,
            forKey: .smoothingLevel
        )
        exportSettings = try container.decode(
            ExportSettings.self,
            forKey: .exportSettings
        )
    }
}
