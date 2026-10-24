import Foundation

/// 以成片时间定位原视频时间，剪掉的画面不会压缩运动记录或让图层提前。
public struct SmartEditOverlayTimeline: Sendable {
    public struct Frame: Sendable {
        public let sourceID: UUID
        public let sourceSeconds: TimeInterval
        public let clockTime: Date?
        public let activitySample: ActivitySample?
        public let activityProgress: ActivityProgress?
        public let configuration: OverlayConfiguration
        public let route: [GeoCoordinate]
        public let elevationProfile: ElevationProfile?
    }

    private let clips: [SmartEditClip]
    private let sources: [UUID: SmartEditMediaSource]
    private let configuration: OverlayConfiguration
    private let activityTimeOffset: TimeInterval
    private let activitySamples: [ActivitySample]
    private let activityTimeline: ActivityTimeline
    private let activityProgressCalculator: ActivityProgressCalculator
    private let activitySourceID: UUID?
    private let activityChannelID: UUID?
    private let routePoints: [TimedRoutePoint]
    private let elevationProfile: ElevationProfile

    private struct TimedRoutePoint: Sendable {
        let timestamp: Date
        let coordinate: GeoCoordinate
    }

    public init(draft: SmartEditDraft) {
        clips = draft.clips.sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }
        sources = Dictionary(uniqueKeysWithValues: draft.sources.map { ($0.id, $0) })
        configuration = draft.overlayConfiguration
        activityTimeOffset = draft.activityTimeOffset
        activitySamples = draft.activitySamples
        activityTimeline = ActivityTimeline()
        activityProgressCalculator = ActivityProgressCalculator(samples: draft.activitySamples)
        activitySourceID = draft.activitySourceID
        activityChannelID = draft.activityChannel?.id
        routePoints = draft.activitySamples.compactMap { sample in
            sample.coordinate.map {
                TimedRoutePoint(timestamp: sample.timestamp, coordinate: $0)
            }
        }
        elevationProfile = ElevationProfile(samples: draft.activitySamples)
    }

    public func frame(at timelineSeconds: TimeInterval) -> Frame? {
        guard timelineSeconds.isFinite, timelineSeconds >= 0 else { return nil }
        var lower = 0
        var upper = clips.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if clips[middle].timelineStartSeconds <= timelineSeconds {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower > 0 else { return nil }
        let clip = clips[lower - 1]
        // 片尾最后一帧也沿用最后的原视频时间，避免渲染时图层突然消失。
        guard timelineSeconds < clip.timelineEndSeconds + 0.035,
              let source = sources[clip.videoSourceID] else { return nil }
        let elapsed = max(0, timelineSeconds - clip.timelineStartSeconds)
        let sourceSeconds = min(clip.videoEndSeconds, clip.videoStartSeconds + elapsed)
        let timestamp = (source.motionStartSnapshot ?? source.capturedAt)?
            .addingTimeInterval(
                (source.motionOffsetSnapshot ?? 0) +
                    activityTimeOffset +
                    clip.activityTimeOffsetSnapshot +
                    sourceSeconds
            )
        let mappedTime = source.motionStartSnapshot.map { start in
            start.addingTimeInterval(
                (source.motionOffsetSnapshot ?? 0) +
                    activityTimeOffset +
                    clip.activityTimeOffsetSnapshot +
                    sourceSeconds
            )
        }
        let hasMatchingActivitySource = activitySourceID.map {
            $0 == activityChannelID
        } ?? true
        let sample = hasMatchingActivitySource
            ? mappedTime.flatMap { activityTimeline.sample(at: $0, in: activitySamples) }
            : nil
        let route = mappedTime.map(routeCoordinates(upTo:)) ?? []
        return Frame(
            sourceID: source.id,
            sourceSeconds: sourceSeconds,
            clockTime: timestamp,
            activitySample: sample,
            activityProgress: hasMatchingActivitySource
                ? activityProgressCalculator.progress(for: sample)
                : nil,
            configuration: source.overlayConfigurationSnapshot ?? configuration,
            route: hasMatchingActivitySource ? route : [],
            elevationProfile: hasMatchingActivitySource && mappedTime != nil
                ? elevationProfile : nil
        )
    }

    private func routeCoordinates(upTo timestamp: Date) -> [GeoCoordinate] {
        if let activitySourceID {
            // 旧草稿未保存运动源 ID 时不限制匹配；新草稿严格校验当前源时间范围。
            guard activityChannelID == activitySourceID else { return [] }
        }
        var lower = 0
        var upper = routePoints.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if routePoints[middle].timestamp <= timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return routePoints.prefix(lower).map(\.coordinate)
    }
}
