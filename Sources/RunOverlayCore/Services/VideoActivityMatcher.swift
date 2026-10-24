import Foundation

public struct VideoActivityMatcher: Sendable {
    public init() {}

    public func match(
        videoStart: Date?,
        duration: TimeInterval,
        activityRange: DateInterval?,
        timeOffset: TimeInterval = 0,
        calibrationMethod: CalibrationMethod = .automatic
    ) -> ActivityMatch {
        guard
            let videoStart,
            let activityRange,
            duration > 0
        else {
            return ActivityMatch(
                status: .unmatched,
                timeOffset: timeOffset,
                calibrationMethod: calibrationMethod
            )
        }

        let adjustedStart = videoStart.addingTimeInterval(timeOffset)
        let videoRange = DateInterval(
            start: adjustedStart,
            duration: duration
        )

        guard let overlap = videoRange.intersection(with: activityRange) else {
            return ActivityMatch(
                status: .unmatched,
                timeOffset: timeOffset,
                calibrationMethod: calibrationMethod
            )
        }

        let coversWholeVideo =
            overlap.start <= videoRange.start &&
            overlap.end >= videoRange.end

        return ActivityMatch(
            status: coversWholeVideo ? .complete : .partial,
            timeOffset: timeOffset,
            matchedRange: overlap,
            calibrationMethod: calibrationMethod
        )
    }

    public func match(
        videos: [VideoItem],
        activityRange: DateInterval
    ) -> [VideoItem] {
        videos.map { video in
            var updated = video
            updated.activityMatch = match(
                videoStart: video.effectiveCapturedAt,
                duration: video.metadata.durationSeconds,
                activityRange: activityRange
            )
            return updated
        }
    }

    public func match(
        videoStart: Date?,
        duration: TimeInterval,
        sidecarCaptureDate: Date?,
        activityRange: DateInterval?,
        timeOffset: TimeInterval = 0,
        calibrationMethod: CalibrationMethod = .automatic
    ) -> ActivityMatch {
        match(
            videoStart: videoStart ?? sidecarCaptureDate,
            duration: duration,
            activityRange: activityRange,
            timeOffset: timeOffset,
            calibrationMethod: calibrationMethod
        )
    }
}
