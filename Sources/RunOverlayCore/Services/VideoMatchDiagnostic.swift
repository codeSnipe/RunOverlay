import Foundation

/// 视频相对运动记录的时间关系，供列表解释匹配失败及部分匹配的原因。
public struct VideoMatchDiagnostic: Equatable, Sendable {
    public let captureSource: VideoCaptureTimeSource
    public let recordedStart: Date?
    public let alignedStart: Date?
    public let secondsFromActivityStart: TimeInterval?
    public let secondsBeforeActivity: TimeInterval
    public let secondsAfterActivity: TimeInterval

    public init(video: VideoItem, activityRange: DateInterval?) {
        captureSource = video.effectiveCaptureTimeSource
        recordedStart = video.effectiveCapturedAt
        alignedStart = recordedStart?.addingTimeInterval(video.activityMatch.timeOffset)
        if let alignedStart, let activityRange {
            secondsFromActivityStart = alignedStart.timeIntervalSince(activityRange.start)
            let duration = video.metadata.durationSeconds.isFinite
                ? max(0, video.metadata.durationSeconds) : 0
            let alignedEnd = alignedStart.addingTimeInterval(duration)
            secondsBeforeActivity = min(
                duration,
                max(0, activityRange.start.timeIntervalSince(alignedStart))
            )
            secondsAfterActivity = min(
                duration,
                max(0, alignedEnd.timeIntervalSince(activityRange.end))
            )
        } else {
            secondsFromActivityStart = nil
            secondsBeforeActivity = 0
            secondsAfterActivity = 0
        }
    }
}

public enum VideoCaptureTimeFormatter {
    public static func format(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter(timeZone: timeZone).string(from: date)
    }

    public static func parse(_ text: String, timeZone: TimeZone = .current) -> Date? {
        formatter(timeZone: timeZone).date(from: text.trimmingCharacters(in: .whitespaces))
    }

    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.isLenient = false
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}
