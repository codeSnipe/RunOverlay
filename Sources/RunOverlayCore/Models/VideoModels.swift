import Foundation

public struct PixelDimensions: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var isPortrait: Bool {
        height > width
    }

    public var displayText: String {
        "\(width) × \(height)"
    }
}

public enum VideoRotation: Int, CaseIterable, Codable, Hashable, Sendable {
    case none = 0
    case clockwise90 = 90
    case halfTurn = 180
    case counterclockwise90 = 270

    public var swapsDimensions: Bool {
        self == .clockwise90 || self == .counterclockwise90
    }

    public func dimensions(afterRotating dimensions: PixelDimensions) -> PixelDimensions {
        swapsDimensions
            ? PixelDimensions(width: dimensions.height, height: dimensions.width)
            : dimensions
    }

    public func rotated(clockwise: Bool) -> VideoRotation {
        let next = (rawValue + (clockwise ? 90 : 270)) % 360
        return VideoRotation(rawValue: next) ?? .none
    }
}

public enum VideoCaptureTimeSource: String, Codable, Hashable, Sendable {
    case container
    case fileName
    case timeResource
    case manual
    case unavailable
}

public struct VideoAssetMetadata: Codable, Hashable, Sendable {
    public var durationSeconds: Double
    public var dimensions: PixelDimensions
    public var frameRate: Double
    public var capturedAt: Date?
    public var captureTimeSource: VideoCaptureTimeSource?
    public var hasAudio: Bool
    public var container: String
    public var fileSizeBytes: Int64

    public init(
        durationSeconds: Double,
        dimensions: PixelDimensions,
        frameRate: Double,
        capturedAt: Date?,
        captureTimeSource: VideoCaptureTimeSource? = nil,
        hasAudio: Bool,
        container: String,
        fileSizeBytes: Int64
    ) {
        self.durationSeconds = durationSeconds
        self.dimensions = dimensions
        self.frameRate = frameRate
        self.capturedAt = capturedAt
        self.captureTimeSource = captureTimeSource
        self.hasAudio = hasAudio
        self.container = container
        self.fileSizeBytes = fileSizeBytes
    }
}

public enum MatchStatus: String, Codable, Hashable, Sendable {
    case pending
    case complete
    case partial
    case unmatched

    public var displayName: String {
        switch self {
        case .pending: RunOverlayLocalization.text("match.pending")
        case .complete: RunOverlayLocalization.text("match.complete")
        case .partial: RunOverlayLocalization.text("match.partial")
        case .unmatched: RunOverlayLocalization.text("match.unmatched")
        }
    }
}

public enum CalibrationMethod: String, Codable, Hashable, Sendable {
    case automatic
    case timeOffset
    case routePosition
}

public struct ActivityMatch: Codable, Hashable, Sendable {
    public var status: MatchStatus
    public var timeOffset: TimeInterval
    public var matchedRange: DateInterval?
    public var calibrationMethod: CalibrationMethod

    public init(
        status: MatchStatus = .pending,
        timeOffset: TimeInterval = 0,
        matchedRange: DateInterval? = nil,
        calibrationMethod: CalibrationMethod = .automatic
    ) {
        self.status = status
        self.timeOffset = timeOffset
        self.matchedRange = matchedRange
        self.calibrationMethod = calibrationMethod
    }
}


public struct VideoItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var fileName: String
    public var fileURL: URL
    public var bookmarkData: Data?
    public var resourceRelativePath: String?
    public var metadata: VideoAssetMetadata
    public var activityMatch: ActivityMatch
    public var overlayOverride: OverlayConfiguration?
    public var timeResource: VideoTimeResource?
    public var rotation: VideoRotation
    public var exportAspectRatio: ExportAspectRatio?
    public var exportMaximumHeight: Int?
    public var cover: VideoCover?
    public var manualCapturedAt: Date?

    public init(
        id: UUID = UUID(),
        fileName: String,
        fileURL: URL,
        bookmarkData: Data? = nil,
        resourceRelativePath: String? = nil,
        metadata: VideoAssetMetadata,
        activityMatch: ActivityMatch = ActivityMatch(),
        overlayOverride: OverlayConfiguration? = nil,
        timeResource: VideoTimeResource? = nil,
        rotation: VideoRotation = .none,
        exportAspectRatio: ExportAspectRatio? = nil,
        exportMaximumHeight: Int? = nil,
        cover: VideoCover? = nil,
        manualCapturedAt: Date? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.bookmarkData = bookmarkData
        self.resourceRelativePath = resourceRelativePath
        self.metadata = metadata
        self.activityMatch = activityMatch
        self.overlayOverride = overlayOverride
        self.timeResource = timeResource
        self.rotation = rotation
        self.exportAspectRatio = exportAspectRatio
        self.exportMaximumHeight = exportMaximumHeight
        self.cover = cover
        self.manualCapturedAt = manualCapturedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case fileURL
        case bookmarkData
        case resourceRelativePath
        case metadata
        case activityMatch
        case overlayOverride
        case timeResource
        case rotation
        case exportAspectRatio
        case exportMaximumHeight
        case cover
        case manualCapturedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        fileURL = try container.decode(URL.self, forKey: .fileURL)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        resourceRelativePath = try container.decodeIfPresent(
            String.self,
            forKey: .resourceRelativePath
        )
        metadata = try container.decode(VideoAssetMetadata.self, forKey: .metadata)
        activityMatch = try container.decode(ActivityMatch.self, forKey: .activityMatch)
        overlayOverride = try container.decodeIfPresent(
            OverlayConfiguration.self,
            forKey: .overlayOverride
        )
        timeResource = try container.decodeIfPresent(
            VideoTimeResource.self,
            forKey: .timeResource
        )
        rotation = try container.decodeIfPresent(VideoRotation.self, forKey: .rotation) ?? .none
        exportAspectRatio = try container.decodeIfPresent(
            ExportAspectRatio.self,
            forKey: .exportAspectRatio
        )
        exportMaximumHeight = try container.decodeIfPresent(
            Int.self,
            forKey: .exportMaximumHeight
        )
        cover = try container.decodeIfPresent(VideoCover.self, forKey: .cover)
        manualCapturedAt = try container.decodeIfPresent(Date.self, forKey: .manualCapturedAt)
    }

    public var effectiveCapturedAt: Date? {
        manualCapturedAt ?? metadata.capturedAt ?? timeResource?.capturedAt
    }

    public var effectiveCaptureTimeSource: VideoCaptureTimeSource {
        if manualCapturedAt != nil { return .manual }
        // 旧项目没有来源字段时保留“来源未知”，避免把视频元数据误认成文件名。
        if metadata.capturedAt != nil {
            return metadata.captureTimeSource ?? .unavailable
        }
        if timeResource?.capturedAt != nil { return .timeResource }
        return .unavailable
    }
}

public struct VideoTimeResource: Codable, Hashable, Sendable {
    public var fileName: String
    public var fileURL: URL
    public var bookmarkData: Data?
    public var resourceRelativePath: String?
    public var capturedAt: Date?

    public init(
        fileName: String,
        fileURL: URL,
        bookmarkData: Data? = nil,
        resourceRelativePath: String? = nil,
        capturedAt: Date?
    ) {
        self.fileName = fileName
        self.fileURL = fileURL
        self.bookmarkData = bookmarkData
        self.resourceRelativePath = resourceRelativePath
        self.capturedAt = capturedAt
    }
}
