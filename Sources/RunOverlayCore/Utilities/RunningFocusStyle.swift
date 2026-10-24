import Foundation

public enum RunningFocusStyle {
    public static func label(
        for kind: OverlayElementKind,
        language: VideoTextLanguage,
        measurementUnit: OverlayMeasurementUnit? = nil
    ) -> String {
        let unit = measurementUnit ?? kind.defaultMeasurementUnit
        if kind == .distance, unit == .miles {
            return RunOverlayLocalization.text("focus.distanceMiles", videoLanguage: language)
        }
        if kind == .pace, unit == .miles {
            return RunOverlayLocalization.text("focus.paceMiles", videoLanguage: language)
        }
        let key: String
        switch kind {
        case .distance: key = "focus.distance"
        case .pace: key = "focus.pace"
        case .elapsedTime: key = "focus.elapsedTime"
        default: return StadiumLiveStyle.label(for: kind, language: language)
        }
        return RunOverlayLocalization.text(key, videoLanguage: language)
    }

    public static func value(
        for kind: OverlayElementKind,
        sample: ActivitySample?,
        activityStart: Date?,
        clockTime: Date?,
        measurementUnit: OverlayMeasurementUnit? = nil,
        clockDisplay: OverlayClockDisplay = .dateTime,
        durationDisplay: OverlayDurationDisplay = .hoursMinutesSeconds
    ) -> String {
        switch kind {
        case .distance:
            return OverlayMeasurementFormatter.distance(
                meters: sample?.distanceMeters,
                unit: measurementUnit ?? .kilometers
            ) ?? "—"
        case .pace:
            guard let pace = OverlayMeasurementFormatter.pace(
                speedMetersPerSecond: sample?.speedMetersPerSecond,
                unit: measurementUnit ?? .kilometers
            ) else {
                return "—′—″"
            }
            return String(format: "%02d′%02d″", pace.minutes, pace.seconds)
        case .elapsedTime:
            return RunOverlayFormatters.activityDuration(
                sample: sample,
                start: activityStart,
                display: durationDisplay
            )
        default:
            return StadiumLiveStyle.value(
                for: kind,
                sample: sample,
                clockTime: clockTime,
                activityStart: activityStart,
                measurementUnit: measurementUnit,
                clockDisplay: clockDisplay,
                durationDisplay: durationDisplay
            )
        }
    }
}
