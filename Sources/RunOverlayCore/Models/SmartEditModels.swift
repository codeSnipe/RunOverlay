import Foundation

public enum LocalSpeechRecognitionStatus: String, Codable, Hashable, Sendable {
    case available
    case noAudio
    case permissionDenied
    case onDeviceUnavailable
    case recognitionFailed
}

public enum SmartEditAnalysisEngine: String, Codable, Hashable, Sendable {
    case local
    case model
}

/// 模型草稿只保存服务商参数，不存储 API 密钥正文或 Keychain 账户名。
public struct SmartEditModelConfiguration: Codable, Hashable, Sendable {
    public var provider: String
    public var baseURL: URL?
    public var modelID: String
    public var region: String

    public init(
        provider: String = "",
        baseURL: URL? = nil,
        modelID: String = "",
        region: String = "中国大陆"
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.modelID = modelID
        self.region = region
    }

    public var keychainAccount: String {
        "com.runoverlay.smart-edit.\(provider.lowercased()).api-key"
    }
}

/// 本机是首版唯一启用的分析方式，保留设置结构供后续增加模型切换。
public struct SmartEditEngineConfiguration: Codable, Hashable, Sendable {
    public var selectedEngine: SmartEditAnalysisEngine
    public var model: SmartEditModelConfiguration

    public init(
        selectedEngine: SmartEditAnalysisEngine = .local,
        model: SmartEditModelConfiguration = SmartEditModelConfiguration()
    ) {
        self.selectedEngine = selectedEngine
        self.model = model
    }
}

/// 本机语音识别结果只用于定位和保护口播，不自动作为字幕烧录或删除依据。
public struct SmartEditSpeechCue: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var startSeconds: TimeInterval
    public var endSeconds: TimeInterval
    public var text: String
    public var confidence: Double
    public var isPrimarySpeakerConfirmed: Bool
    public var isLocked: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case startSeconds
        case endSeconds
        case text
        case confidence
        case isPrimarySpeakerConfirmed
        case isLocked
    }

    public init(
        id: UUID = UUID(),
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        text: String,
        confidence: Double,
        isPrimarySpeakerConfirmed: Bool = false,
        isLocked: Bool = true
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.confidence = confidence
        self.isPrimarySpeakerConfirmed = isPrimarySpeakerConfirmed
        self.isLocked = isLocked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startSeconds = try container.decode(TimeInterval.self, forKey: .startSeconds)
        endSeconds = try container.decode(TimeInterval.self, forKey: .endSeconds)
        text = try container.decode(String.self, forKey: .text)
        confidence = try container.decode(Double.self, forKey: .confidence)
        isPrimarySpeakerConfirmed = try container.decodeIfPresent(
            Bool.self,
            forKey: .isPrimarySpeakerConfirmed
        ) ?? false
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? true
    }
}

public struct SmartEditMediaSource: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var fileName: String
    public var fileURL: URL
    public var bookmarkData: Data?
    public var originalVideoID: UUID?
    public var motionStartSnapshot: Date?
    public var motionOffsetSnapshot: TimeInterval?
    public var overlayConfigurationSnapshot: OverlayConfiguration?
    public var durationSeconds: TimeInterval
    public var dimensions: PixelDimensions
    public var capturedAt: Date?
    public var hasAudio: Bool
    public var audioStartInVideoSeconds: TimeInterval
    public var sceneBoundaries: [TimeInterval]
    public var quietRanges: [SmartEditQuietRange]
    public var detectedSpeechRanges: [SmartEditQuietRange]
    public var speechRecognitionStatus: LocalSpeechRecognitionStatus
    public var speechCues: [SmartEditSpeechCue]

    private enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case fileURL
        case bookmarkData
        case originalVideoID
        case motionStartSnapshot
        case motionOffsetSnapshot
        case overlayConfigurationSnapshot
        case durationSeconds
        case dimensions
        case capturedAt
        case hasAudio
        case audioStartInVideoSeconds
        case sceneBoundaries
        case quietRanges
        case detectedSpeechRanges
        case speechRecognitionStatus
        case speechCues
    }

    public init(
        id: UUID = UUID(),
        fileName: String,
        fileURL: URL,
        bookmarkData: Data? = nil,
        originalVideoID: UUID? = nil,
        motionStartSnapshot: Date? = nil,
        motionOffsetSnapshot: TimeInterval? = nil,
        overlayConfigurationSnapshot: OverlayConfiguration? = nil,
        durationSeconds: TimeInterval,
        dimensions: PixelDimensions,
        capturedAt: Date? = nil,
        hasAudio: Bool,
        audioStartInVideoSeconds: TimeInterval = 0,
        sceneBoundaries: [TimeInterval] = [],
        quietRanges: [SmartEditQuietRange] = [],
        detectedSpeechRanges: [SmartEditQuietRange] = [],
        speechRecognitionStatus: LocalSpeechRecognitionStatus = .noAudio,
        speechCues: [SmartEditSpeechCue] = []
    ) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.bookmarkData = bookmarkData
        self.originalVideoID = originalVideoID
        self.motionStartSnapshot = motionStartSnapshot
        self.motionOffsetSnapshot = motionOffsetSnapshot
        self.overlayConfigurationSnapshot = overlayConfigurationSnapshot
        self.durationSeconds = durationSeconds
        self.dimensions = dimensions
        self.capturedAt = capturedAt
        self.hasAudio = hasAudio
        self.audioStartInVideoSeconds = audioStartInVideoSeconds
        self.sceneBoundaries = sceneBoundaries
        self.quietRanges = quietRanges
        self.detectedSpeechRanges = detectedSpeechRanges
        self.speechRecognitionStatus = speechRecognitionStatus
        self.speechCues = speechCues
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        fileName = try values.decode(String.self, forKey: .fileName)
        fileURL = try values.decode(URL.self, forKey: .fileURL)
        bookmarkData = try values.decodeIfPresent(Data.self, forKey: .bookmarkData)
        originalVideoID = try values.decodeIfPresent(UUID.self, forKey: .originalVideoID)
        motionStartSnapshot = try values.decodeIfPresent(Date.self, forKey: .motionStartSnapshot)
        motionOffsetSnapshot = try values.decodeIfPresent(
            TimeInterval.self,
            forKey: .motionOffsetSnapshot
        )
        overlayConfigurationSnapshot = try values.decodeIfPresent(
            OverlayConfiguration.self,
            forKey: .overlayConfigurationSnapshot
        )
        durationSeconds = try values.decode(TimeInterval.self, forKey: .durationSeconds)
        dimensions = try values.decode(PixelDimensions.self, forKey: .dimensions)
        capturedAt = try values.decodeIfPresent(Date.self, forKey: .capturedAt)
        hasAudio = try values.decode(Bool.self, forKey: .hasAudio)
        audioStartInVideoSeconds = try values.decodeIfPresent(
            TimeInterval.self,
            forKey: .audioStartInVideoSeconds
        ) ?? 0
        sceneBoundaries = try values.decodeIfPresent(
            [TimeInterval].self,
            forKey: .sceneBoundaries
        ) ?? []
        quietRanges = try values.decodeIfPresent(
            [SmartEditQuietRange].self,
            forKey: .quietRanges
        ) ?? []
        detectedSpeechRanges = try values.decodeIfPresent(
            [SmartEditQuietRange].self,
            forKey: .detectedSpeechRanges
        ) ?? []
        speechRecognitionStatus = try values.decodeIfPresent(
            LocalSpeechRecognitionStatus.self,
            forKey: .speechRecognitionStatus
        ) ?? .noAudio
        speechCues = try values.decodeIfPresent(
            [SmartEditSpeechCue].self,
            forKey: .speechCues
        ) ?? []
    }
}

/// 声音波形确认安静的时间段，不将“未识别到语音”误当作“没有讲话”。
public struct SmartEditQuietRange: Codable, Hashable, Sendable {
    public let startSeconds: TimeInterval
    public let endSeconds: TimeInterval

    public init(startSeconds: TimeInterval, endSeconds: TimeInterval) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

/// 画面片段引用视频源与视频入出点；关联的人声文稿始终独立保存在音轨草稿中。
public struct SmartEditClip: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var videoSourceID: UUID
    public var videoStartSeconds: TimeInterval
    public var videoEndSeconds: TimeInterval
    public var timelineStartSeconds: TimeInterval
    public var transcript: String
    public var speechConfidence: Double?
    public var isLocked: Bool
    public var keepsSourceAudio: Bool
    public var activityTimeOffsetSnapshot: TimeInterval
    public var overlayConfiguration: OverlayConfiguration

    private enum CodingKeys: String, CodingKey {
        case id
        case videoSourceID
        case videoStartSeconds
        case videoEndSeconds
        case timelineStartSeconds
        case transcript
        case speechConfidence
        case isLocked
        case keepsSourceAudio
        case activityTimeOffsetSnapshot
        case overlayConfiguration
    }

    public init(
        id: UUID = UUID(),
        videoSourceID: UUID,
        videoStartSeconds: TimeInterval,
        videoEndSeconds: TimeInterval,
        timelineStartSeconds: TimeInterval = 0,
        transcript: String = "",
        speechConfidence: Double? = nil,
        isLocked: Bool = false,
        keepsSourceAudio: Bool = false,
        activityTimeOffsetSnapshot: TimeInterval = 0,
        overlayConfiguration: OverlayConfiguration = .preset(.runningFocus)
    ) {
        self.id = id
        self.videoSourceID = videoSourceID
        self.videoStartSeconds = videoStartSeconds
        self.videoEndSeconds = videoEndSeconds
        self.timelineStartSeconds = timelineStartSeconds
        self.transcript = transcript
        self.speechConfidence = speechConfidence
        self.isLocked = isLocked
        self.keepsSourceAudio = keepsSourceAudio
        self.activityTimeOffsetSnapshot = activityTimeOffsetSnapshot
        self.overlayConfiguration = overlayConfiguration
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        videoSourceID = try values.decode(UUID.self, forKey: .videoSourceID)
        videoStartSeconds = try values.decode(TimeInterval.self, forKey: .videoStartSeconds)
        videoEndSeconds = try values.decode(TimeInterval.self, forKey: .videoEndSeconds)
        timelineStartSeconds = try values.decode(TimeInterval.self, forKey: .timelineStartSeconds)
        transcript = try values.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        speechConfidence = try values.decodeIfPresent(Double.self, forKey: .speechConfidence)
        isLocked = try values.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        keepsSourceAudio = try values.decodeIfPresent(Bool.self, forKey: .keepsSourceAudio) ?? false
        activityTimeOffsetSnapshot = try values.decodeIfPresent(
            TimeInterval.self,
            forKey: .activityTimeOffsetSnapshot
        ) ?? 0
        overlayConfiguration = try values.decodeIfPresent(
            OverlayConfiguration.self,
            forKey: .overlayConfiguration
        ) ?? .preset(.runningFocus)
    }

    public var durationSeconds: TimeInterval {
        max(0, videoEndSeconds - videoStartSeconds)
    }

    public var timelineEndSeconds: TimeInterval {
        timelineStartSeconds + durationSeconds
    }
}

/// 独立音轨的源时间与成片时间映射；默认完整连续保留素材原声。
public struct SmartEditAudioSegment: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var sourceID: UUID
    public var sourceStartSeconds: TimeInterval
    public var sourceEndSeconds: TimeInterval
    public var timelineStartSeconds: TimeInterval
    public var volume: Double
    public var isLocked: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceID
        case sourceStartSeconds
        case sourceEndSeconds
        case timelineStartSeconds
        case volume
        case isLocked
    }

    public init(
        id: UUID = UUID(),
        sourceID: UUID,
        sourceStartSeconds: TimeInterval,
        sourceEndSeconds: TimeInterval,
        timelineStartSeconds: TimeInterval,
        volume: Double = 1,
        isLocked: Bool = true
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceStartSeconds = sourceStartSeconds
        self.sourceEndSeconds = sourceEndSeconds
        self.timelineStartSeconds = timelineStartSeconds
        self.volume = volume
        self.isLocked = isLocked
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        sourceID = try values.decode(UUID.self, forKey: .sourceID)
        sourceStartSeconds = try values.decode(TimeInterval.self, forKey: .sourceStartSeconds)
        sourceEndSeconds = try values.decode(TimeInterval.self, forKey: .sourceEndSeconds)
        timelineStartSeconds = try values.decode(TimeInterval.self, forKey: .timelineStartSeconds)
        volume = try values.decodeIfPresent(Double.self, forKey: .volume) ?? 1
        isLocked = try values.decodeIfPresent(Bool.self, forKey: .isLocked) ?? true
    }

    public var durationSeconds: TimeInterval {
        max(0, sourceEndSeconds - sourceStartSeconds)
    }

    public var timelineEndSeconds: TimeInterval {
        timelineStartSeconds + durationSeconds
    }
}

public struct SmartEditDraft: Codable, Hashable, Sendable, Identifiable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var sources: [SmartEditMediaSource]
    public var clips: [SmartEditClip]
    public var audioSegments: [SmartEditAudioSegment]
    public var aspectRatio: ExportAspectRatio
    public var maximumHeight: Int
    public var codec: ExportSettings.Codec
    public var speechLocaleIdentifier: String
    public var engineConfiguration: SmartEditEngineConfiguration
    public var activitySamples: [ActivitySample]
    public var activitySourceID: UUID?
    public var activityChannel: ActivitySource?
    public var activityTimeOffset: TimeInterval
    public var activityStartSnapshot: Date?
    public var videoTextLanguage: VideoTextLanguage
    public var overlayConfiguration: OverlayConfiguration

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sources: [SmartEditMediaSource] = [],
        clips: [SmartEditClip] = [],
        audioSegments: [SmartEditAudioSegment] = [],
        aspectRatio: ExportAspectRatio = .source,
        maximumHeight: Int = 1_080,
        codec: ExportSettings.Codec = .h264,
        speechLocaleIdentifier: String = "zh-CN",
        engineConfiguration: SmartEditEngineConfiguration = SmartEditEngineConfiguration(),
        activitySamples: [ActivitySample] = [],
        activitySourceID: UUID? = nil,
        activityChannel: ActivitySource? = nil,
        activityTimeOffset: TimeInterval = 0,
        activityStartSnapshot: Date? = nil,
        videoTextLanguage: VideoTextLanguage = .chinese,
        overlayConfiguration: OverlayConfiguration = .preset(.runningFocus)
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sources = sources
        self.clips = clips
        self.audioSegments = audioSegments
        self.aspectRatio = aspectRatio
        self.maximumHeight = maximumHeight
        self.codec = codec
        self.speechLocaleIdentifier = speechLocaleIdentifier
        self.engineConfiguration = engineConfiguration
        self.activitySamples = activitySamples
        self.activitySourceID = activitySourceID
        self.activityChannel = activityChannel
        self.activityTimeOffset = activityTimeOffset
        self.activityStartSnapshot = activityStartSnapshot
        self.videoTextLanguage = videoTextLanguage
        self.overlayConfiguration = overlayConfiguration
    }

    public var durationSeconds: TimeInterval {
        max(
            max(
                clips.map(\.timelineEndSeconds).max() ?? 0,
                clips.map(\.durationSeconds).max() ?? 0
            ),
            audioSegments.map(\.timelineEndSeconds).max() ?? 0
        )
    }

    public var preservedSpeechCueCount: Int {
        sources.reduce(0) { $0 + $1.speechCues.filter(\.isLocked).count }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case name
        case createdAt
        case updatedAt
        case sources
        case clips
        case audioSegments
        case aspectRatio
        case maximumHeight
        case codec
        case speechLocaleIdentifier
        case engineConfiguration
        case activitySamples
        case activitySourceID
        case activityChannel
        case activityTimeOffset
        case activityStartSnapshot
        case videoTextLanguage
        case overlayConfiguration
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(sources, forKey: .sources)
        try container.encode(clips, forKey: .clips)
        try container.encode(audioSegments, forKey: .audioSegments)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encode(maximumHeight, forKey: .maximumHeight)
        try container.encode(codec, forKey: .codec)
        try container.encode(speechLocaleIdentifier, forKey: .speechLocaleIdentifier)
        try container.encode(engineConfiguration, forKey: .engineConfiguration)
        try container.encode(activitySamples, forKey: .activitySamples)
        try container.encodeIfPresent(activitySourceID, forKey: .activitySourceID)
        try container.encodeIfPresent(activityChannel, forKey: .activityChannel)
        try container.encode(activityTimeOffset, forKey: .activityTimeOffset)
        try container.encodeIfPresent(activityStartSnapshot, forKey: .activityStartSnapshot)
        try container.encode(videoTextLanguage, forKey: .videoTextLanguage)
        try container.encode(overlayConfiguration, forKey: .overlayConfiguration)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        sources = try container.decode([SmartEditMediaSource].self, forKey: .sources)
        aspectRatio = try container.decode(ExportAspectRatio.self, forKey: .aspectRatio)
        maximumHeight = try container.decode(Int.self, forKey: .maximumHeight)
        codec = try container.decode(ExportSettings.Codec.self, forKey: .codec)
        speechLocaleIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .speechLocaleIdentifier
        ) ?? "zh-CN"
        engineConfiguration = try container.decodeIfPresent(
            SmartEditEngineConfiguration.self,
            forKey: .engineConfiguration
        ) ?? SmartEditEngineConfiguration()
        activitySamples = try container.decodeIfPresent(
            [ActivitySample].self,
            forKey: .activitySamples
        ) ?? []
        activitySourceID = try container.decodeIfPresent(UUID.self, forKey: .activitySourceID)
        activityChannel = try container.decodeIfPresent(
            ActivitySource.self,
            forKey: .activityChannel
        )
        activityTimeOffset = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .activityTimeOffset
        ) ?? 0
        activityStartSnapshot = try container.decodeIfPresent(
            Date.self,
            forKey: .activityStartSnapshot
        )
        videoTextLanguage = try container.decodeIfPresent(
            VideoTextLanguage.self,
            forKey: .videoTextLanguage
        ) ?? .chinese
        overlayConfiguration = try container.decodeIfPresent(
            OverlayConfiguration.self,
            forKey: .overlayConfiguration
        ) ?? .preset(.runningFocus)
        if schemaVersion >= Self.currentSchemaVersion,
           let currentClips = try? container.decode([SmartEditClip].self, forKey: .clips) {
            clips = currentClips
            audioSegments = try container.decodeIfPresent(
                [SmartEditAudioSegment].self,
                forKey: .audioSegments
            ) ?? []
        } else {
            let legacyClips = try container.decode(
                [LegacySmartEditClip].self,
                forKey: .clips
            )
            clips = Self.migrateVideoClips(
                legacyClips,
                sources: sources,
                audioSegments: Self.migrateAudioSegments(legacyClips, sources: sources)
            )
            audioSegments = Self.migrateAudioSegments(legacyClips, sources: sources)
            schemaVersion = Self.currentSchemaVersion
        }
    }

    private struct LegacySmartEditClip: Decodable {
        var id: UUID
        var videoSourceID: UUID
        var videoStartSeconds: TimeInterval
        var videoEndSeconds: TimeInterval
        var audioSourceID: UUID?
        var audioStartSeconds: TimeInterval?
        var audioEndSeconds: TimeInterval?
        var transcript: String
        var speechConfidence: Double?
        var isLocked: Bool
        var keepsSourceAudio: Bool
    }

    private static func migrateVideoClips(
        _ legacyClips: [LegacySmartEditClip],
        sources: [SmartEditMediaSource],
        audioSegments: [SmartEditAudioSegment]
    ) -> [SmartEditClip] {
        let sourceIDs = Set(sources.map(\.id))
        var sourceOrder = Array(NSOrderedSet(array: legacyClips.map(\.videoSourceID))) as? [UUID]
            ?? []
        for sourceID in sources.map(\.id) where !sourceOrder.contains(sourceID) {
            sourceOrder.append(sourceID)
        }
        sourceOrder = sourceOrder.filter(sourceIDs.contains)
        sourceOrder = sources.sorted { lhs, rhs in
            let left = lhs.capturedAt
            let right = rhs.capturedAt
            if let left, let right, left != right { return left < right }
            if left != nil && right == nil { return true }
            if left == nil && right != nil { return false }
            return (sources.firstIndex(where: { $0.id == lhs.id }) ?? .max) <
                (sources.firstIndex(where: { $0.id == rhs.id }) ?? .max)
        }.map(\.id).filter { sourceOrder.contains($0) }
        let audioSourceIDs = Set(audioSegments.map(\.sourceID))
        let audioOnlySources = sources.map(\.id).filter { sourceID in
            audioSourceIDs.contains(sourceID) && !legacyClips.contains { clip in
                clip.videoSourceID == sourceID
            }
        }
        sourceOrder.sort { lhs, rhs in
            let left = sources.first(where: { $0.id == lhs })?.capturedAt
            let right = sources.first(where: { $0.id == rhs })?.capturedAt
            if let left, let right, left != right { return left < right }
            if left != nil && right == nil { return true }
            if left == nil && right != nil { return false }
            return (sources.firstIndex(where: { $0.id == lhs }) ?? .max) <
                (sources.firstIndex(where: { $0.id == rhs }) ?? .max)
        }
        var playbackOrder = sourceOrder.filter { !audioOnlySources.contains($0) }
        playbackOrder.append(contentsOf: audioOnlySources.sorted { lhs, rhs in
            let left = sources.first(where: { $0.id == lhs })?.capturedAt
            let right = sources.first(where: { $0.id == rhs })?.capturedAt
            if let left, let right, left != right { return left < right }
            if left != nil && right == nil { return true }
            if left == nil && right != nil { return false }
            return (sources.firstIndex(where: { $0.id == lhs }) ?? .max) <
                (sources.firstIndex(where: { $0.id == rhs }) ?? .max)
        })
        _ = audioSegments
        var timelineStart: TimeInterval = 0
        return playbackOrder.flatMap { sourceID -> [SmartEditClip] in
            let sourceClips = legacyClips.filter {
                $0.videoSourceID == sourceID
            }.sorted { $0.videoStartSeconds < $1.videoStartSeconds }
            let migrated = sourceClips.compactMap { legacy -> SmartEditClip? in
                let clip = SmartEditClip(
                    id: legacy.id,
                    videoSourceID: legacy.videoSourceID,
                    videoStartSeconds: legacy.videoStartSeconds,
                    videoEndSeconds: legacy.videoEndSeconds,
                    timelineStartSeconds: timelineStart,
                    transcript: legacy.transcript,
                    speechConfidence: legacy.speechConfidence,
                    isLocked: false,
                    keepsSourceAudio: false
                )
                guard clip.durationSeconds.isFinite, clip.durationSeconds > 0 else {
                    return nil
                }
                timelineStart += clip.durationSeconds
                return clip
            }
            return migrated
        }
    }

    private static func migrateAudioSegments(
        _ legacyClips: [LegacySmartEditClip],
        sources: [SmartEditMediaSource]
    ) -> [SmartEditAudioSegment] {
        var sourceOrder: [UUID] = []
        var segmentsBySource: [UUID: [LegacySmartEditClip]] = [:]
        for clip in legacyClips {
            guard let sourceID = clip.audioSourceID,
                  clip.audioStartSeconds != nil,
                  clip.audioEndSeconds != nil else {
                continue
            }
            if segmentsBySource[sourceID] == nil {
                sourceOrder.append(sourceID)
            }
            segmentsBySource[sourceID, default: []].append(clip)
        }

        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        var result: [SmartEditAudioSegment] = []
        for sourceID in sourceOrder {
            guard let source = sourcesByID[sourceID] else { continue }
            let clips = (segmentsBySource[sourceID] ?? []).sorted {
                ($0.audioStartSeconds ?? 0) < ($1.audioStartSeconds ?? 0)
            }
            var ranges: [(start: Double, end: Double)] = []
            for clip in clips {
                guard let start = clip.audioStartSeconds,
                      let end = clip.audioEndSeconds,
                      start.isFinite, end.isFinite,
                      start >= 0, end > start,
                      end <= source.durationSeconds + 0.001 else {
                    continue
                }
                if let last = ranges.last, start <= last.end + 0.05 {
                    ranges[ranges.count - 1].end = max(last.end, end)
                } else {
                    ranges.append((start, end))
                }
            }
            for range in ranges {
                result.append(SmartEditAudioSegment(
                    sourceID: sourceID,
                    sourceStartSeconds: range.start,
                    sourceEndSeconds: range.end,
                    timelineStartSeconds: 0
                ))
            }
        }
        return result
    }
}

public struct SmartEditTimelineEditor: Sendable {
    public init() {}

    public func canMoveClips(in draft: SmartEditDraft) -> Bool {
        Set(draft.clips.map(\.videoSourceID)).count <= 1
    }

    /// 调整单一来源内部镜头顺序；跨来源重排暂不开放，防止口播错序。
    public func movingClip(
        _ clipID: UUID,
        by offset: Int,
        in draft: SmartEditDraft
    ) -> SmartEditDraft? {
        guard Set(draft.clips.map(\.videoSourceID)).count <= 1 else { return nil }
        guard offset != 0,
              let currentIndex = draft.clips.firstIndex(where: { $0.id == clipID }) else {
            return nil
        }
        let destinationIndex = currentIndex + offset
        guard draft.clips.indices.contains(destinationIndex) else { return nil }

        var updated = draft
        let movedClip = updated.clips.remove(at: currentIndex)
        updated.clips.insert(movedClip, at: destinationIndex)
        var timelineStart: TimeInterval = 0
        for index in updated.clips.indices {
            updated.clips[index].timelineStartSeconds = timelineStart
            timelineStart += updated.clips[index].durationSeconds
        }
        updated.updatedAt = Date()
        return updated
    }

    public func updatingClipRange(
        _ clipID: UUID,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        in draft: SmartEditDraft
    ) -> SmartEditDraft? {
        guard startSeconds.isFinite, endSeconds.isFinite,
              let index = draft.clips.firstIndex(where: { $0.id == clipID }),
              let source = draft.sources.first(where: {
                  $0.id == draft.clips[index].videoSourceID
              }),
              startSeconds >= 0,
              endSeconds > startSeconds,
              endSeconds <= source.durationSeconds else {
            return nil
        }
        var updated = draft
        let oldDuration = updated.clips[index].durationSeconds
        updated.clips[index].videoStartSeconds = startSeconds
        updated.clips[index].videoEndSeconds = endSeconds
        let difference = endSeconds - startSeconds - oldDuration
        if abs(difference) > 0.000_1 {
            for followingIndex in updated.clips.indices where followingIndex > index {
                updated.clips[followingIndex].timelineStartSeconds += difference
            }
        }
        updated.updatedAt = Date()
        return updated
    }

    /// 在单个画面片段内切分画面，音频入出点与口播文字内容不变。
    public func splittingClip(
        _ clipID: UUID,
        at sourceSeconds: TimeInterval,
        in draft: SmartEditDraft
    ) -> SmartEditDraft? {
        guard sourceSeconds.isFinite,
              let index = draft.clips.firstIndex(where: { $0.id == clipID }) else {
            return nil
        }
        let original = draft.clips[index]
        guard sourceSeconds > original.videoStartSeconds + 0.2,
              sourceSeconds < original.videoEndSeconds - 0.2 else {
            return nil
        }
        var updated = draft
        let originalEnd = original.videoEndSeconds
        let secondHalf = SmartEditClip(
            videoSourceID: original.videoSourceID,
            videoStartSeconds: sourceSeconds,
            videoEndSeconds: originalEnd,
            timelineStartSeconds: original.timelineStartSeconds +
                sourceSeconds - original.videoStartSeconds,
            transcript: original.transcript,
            speechConfidence: original.speechConfidence,
            isLocked: original.isLocked,
            keepsSourceAudio: false,
            activityTimeOffsetSnapshot: original.activityTimeOffsetSnapshot,
            overlayConfiguration: original.overlayConfiguration
        )
        updated.clips[index].videoEndSeconds = sourceSeconds
        updated.clips.insert(secondHalf, at: index + 1)
        for followingIndex in updated.clips.indices where followingIndex > index + 1 {
            updated.clips[followingIndex].timelineStartSeconds +=
                secondHalf.durationSeconds
        }
        updated.updatedAt = Date()
        return updated
    }

    public func trimmingClipEnd(
        _ clipID: UUID,
        to sourceSeconds: TimeInterval,
        in draft: SmartEditDraft
    ) -> SmartEditDraft? {
        guard sourceSeconds.isFinite,
              let index = draft.clips.firstIndex(where: { $0.id == clipID }),
              sourceSeconds > draft.clips[index].videoStartSeconds + 0.2,
              sourceSeconds < draft.clips[index].videoEndSeconds - 0.1 else {
            return nil
        }
        var updated = draft
        let oldEnd = updated.clips[index].videoEndSeconds
        let difference = sourceSeconds - oldEnd
        updated.clips[index].videoEndSeconds = sourceSeconds
        for followingIndex in updated.clips.indices where followingIndex > index {
            updated.clips[followingIndex].timelineStartSeconds += difference
        }
        updated.updatedAt = Date()
        return updated
    }
}
