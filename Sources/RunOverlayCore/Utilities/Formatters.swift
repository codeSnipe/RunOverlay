import Foundation

public enum RunOverlayFormatters {
    public static func clockDateTime(
        _ date: Date?,
        timeZone: TimeZone = .current
    ) -> String {
        "\(clockDate(date, timeZone: timeZone)) \(clockTime(date, timeZone: timeZone))"
    }

    public static func clockDate(
        _ date: Date?,
        timeZone: TimeZone = .current
    ) -> String {
        guard let date else {
            return "—-—-—"
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return "—-—-—"
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func clockTime(
        _ date: Date?,
        timeZone: TimeZone = .current
    ) -> String {
        guard let date else {
            return "—:—:—"
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.hour, .minute, .second],
            from: date
        )
        guard let hour = components.hour,
              let minute = components.minute,
              let second = components.second else {
            return "—:—:—"
        }
        return String(format: "%02d:%02d:%02d", hour, minute, second)
    }

    public static func clock(
        _ date: Date?,
        display: OverlayClockDisplay,
        timeZone: TimeZone = .current
    ) -> String {
        switch display {
        case .dateTime: clockDateTime(date, timeZone: timeZone)
        case .date: clockDate(date, timeZone: timeZone)
        case .time: clockTime(date, timeZone: timeZone)
        }
    }

    public static func activityDuration(
        sample: ActivitySample?,
        start: Date?,
        display: OverlayDurationDisplay
    ) -> String {
        guard let sample, let start else {
            return display == .hoursMinutesSeconds ? "—:—:—" : "—:—"
        }
        let seconds = sample.timestamp.timeIntervalSince(start)
        guard seconds.isFinite, seconds >= 0 else {
            return display == .hoursMinutesSeconds ? "—:—:—" : "—:—"
        }
        switch display {
        case .adaptive: return duration(seconds)
        case .hoursMinutesSeconds:
            let value = Int(seconds.rounded(.down))
            return String(
                format: "%02d:%02d:%02d",
                value / 3_600,
                (value % 3_600) / 60,
                value % 60
            )
        }
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "00:00"
        }

        let roundedSeconds = Int(seconds.rounded(.down))
        let hours = roundedSeconds / 3_600
        let minutes = (roundedSeconds % 3_600) / 60
        let remainingSeconds = roundedSeconds % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                remainingSeconds
            )
        }

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    public static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }
}
