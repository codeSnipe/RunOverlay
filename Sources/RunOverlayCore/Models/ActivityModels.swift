import Foundation

public struct GeoCoordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct ActivitySample: Codable, Hashable, Sendable {
    public var timestamp: Date
    public var coordinate: GeoCoordinate?
    public var distanceMeters: Double?
    public var speedMetersPerSecond: Double?
    public var heartRate: Double?
    public var cadence: Double?
    public var power: Double?
    public var altitudeMeters: Double?
    public var ascentMeters: Double?
    public var caloriesKilocalories: Double?

    public init(
        timestamp: Date,
        coordinate: GeoCoordinate? = nil,
        distanceMeters: Double? = nil,
        speedMetersPerSecond: Double? = nil,
        heartRate: Double? = nil,
        cadence: Double? = nil,
        power: Double? = nil,
        altitudeMeters: Double? = nil,
        ascentMeters: Double? = nil,
        caloriesKilocalories: Double? = nil
    ) {
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.distanceMeters = distanceMeters
        self.speedMetersPerSecond = speedMetersPerSecond
        self.heartRate = heartRate
        self.cadence = cadence
        self.power = power
        self.altitudeMeters = altitudeMeters
        self.ascentMeters = ascentMeters
        self.caloriesKilocalories = caloriesKilocalories
    }
}

public enum ActivityDataChannel: String, CaseIterable, Codable, Hashable, Sendable {
    case location
    case distance
    case speed
    case heartRate
    case cadence
    case power
    case altitude
    case ascent
    case calories

    public var displayName: String {
        switch self {
        case .location: RunOverlayLocalization.text("channel.location")
        case .distance: RunOverlayLocalization.text("overlay.distance")
        case .speed: RunOverlayLocalization.text("channel.speed")
        case .heartRate: RunOverlayLocalization.text("overlay.heartRate")
        case .cadence: RunOverlayLocalization.text("overlay.cadence")
        case .power: RunOverlayLocalization.text("overlay.power")
        case .altitude: RunOverlayLocalization.text("overlay.altitude")
        case .ascent: RunOverlayLocalization.text("overlay.ascent")
        case .calories: RunOverlayLocalization.text("overlay.calories")
        }
    }
}

public enum ActivityFileKind: String, Codable, Hashable, Sendable {
    case fit
    case gpx
}

public struct ActivitySource: Codable, Hashable, Sendable {
    public var id: UUID
    public var fileName: String
    public var fileURL: URL
    public var bookmarkData: Data?
    public var resourceRelativePath: String?
    public var kind: ActivityFileKind
    public var timeRange: DateInterval?
    public var sampleCount: Int
    public var availableChannels: Set<ActivityDataChannel>

    public init(
        id: UUID = UUID(),
        fileName: String,
        fileURL: URL,
        bookmarkData: Data? = nil,
        resourceRelativePath: String? = nil,
        kind: ActivityFileKind,
        timeRange: DateInterval? = nil,
        sampleCount: Int = 0,
        availableChannels: Set<ActivityDataChannel> = []
    ) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.bookmarkData = bookmarkData
        self.resourceRelativePath = resourceRelativePath
        self.kind = kind
        self.timeRange = timeRange
        self.sampleCount = sampleCount
        self.availableChannels = availableChannels
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case fileURL
        case bookmarkData
        case resourceRelativePath
        case kind
        case timeRange
        case sampleCount
        case availableChannels
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
        kind = try container.decode(ActivityFileKind.self, forKey: .kind)
        timeRange = try container.decodeIfPresent(DateInterval.self, forKey: .timeRange)
        sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        availableChannels = try container.decodeIfPresent(
            Set<ActivityDataChannel>.self,
            forKey: .availableChannels
        ) ?? []
    }
}

public struct ParsedActivity: Hashable, Sendable {
    public var kind: ActivityFileKind
    public var samples: [ActivitySample]
    public var timeRange: DateInterval
    public var availableChannels: Set<ActivityDataChannel>

    public init(
        kind: ActivityFileKind,
        samples: [ActivitySample],
        timeRange: DateInterval,
        availableChannels: Set<ActivityDataChannel>
    ) {
        self.kind = kind
        self.samples = samples
        self.timeRange = timeRange
        self.availableChannels = availableChannels
    }
}
