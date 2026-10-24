import Foundation

public enum StadiumLiveStyle {
    public static func label(
        for kind: OverlayElementKind,
        language: VideoTextLanguage = .chinese
    ) -> String {
        let key: String
        switch kind {
        case .pace: key = "stadium.pace"
        case .calories: key = "stadium.calories"
        case .altitude: key = "stadium.altitude"
        case .distance: key = "stadium.distance"
        case .elapsedTime: key = "stadium.elapsedTime"
        case .heartRate: key = "stadium.heartRate"
        case .cadence: key = "stadium.cadence"
        case .power: key = "stadium.power"
        case .ascent: key = "stadium.ascent"
        default: return ""
        }
        return RunOverlayLocalization.text(key, videoLanguage: language)
    }

    public static func value(
        for kind: OverlayElementKind,
        sample: ActivitySample?,
        clockTime: Date?,
        activityStart: Date? = nil,
        measurementUnit: OverlayMeasurementUnit? = nil,
        clockDisplay: OverlayClockDisplay = .dateTime,
        durationDisplay: OverlayDurationDisplay = .adaptive
    ) -> String {
        switch kind {
        case .pace:
            let unit = measurementUnit ?? .kilometers
            guard let pace = OverlayMeasurementFormatter.pace(
                speedMetersPerSecond: sample?.speedMetersPerSecond,
                unit: unit
            ) else {
                return "—"
            }
            let text = String(format: "%d′%02d″", pace.minutes, pace.seconds)
            return unit == .miles ? "\(text) /MI" : text
        case .calories:
            guard let calories = sample?.caloriesKilocalories,
                  calories.isFinite else {
                return "— KCAL"
            }
            return String(format: "%.1f KCAL", calories)
        case .heartRate:
            guard let heartRate = sample?.heartRate,
                  heartRate.isFinite else {
                return "—"
            }
            return String(Int(heartRate.rounded()))
        case .altitude:
            let unit = measurementUnit ?? .meters
            let value = OverlayMeasurementFormatter.elevation(
                meters: sample?.altitudeMeters,
                unit: unit
            ) ?? "—"
            return "\(value) \(unit == .feet ? "FT" : "M")"
        case .distance:
            let unit = measurementUnit ?? .kilometers
            let value = OverlayMeasurementFormatter.distance(
                meters: sample?.distanceMeters,
                unit: unit
            ) ?? "—"
            return "\(value) \(unit == .miles ? "MI" : "KM")"
        case .clockTime:
            return RunOverlayFormatters.clock(clockTime, display: clockDisplay)
                .replacingOccurrences(of: "-", with: "/")
        case .elapsedTime:
            return RunOverlayFormatters.activityDuration(
                sample: sample,
                start: activityStart,
                display: durationDisplay
            )
        case .cadence:
            return sample?.cadence.flatMap {
                $0.isFinite ? "\(Int($0.rounded())) SPM" : nil
            } ?? "— SPM"
        case .power:
            return sample?.power.flatMap {
                $0.isFinite ? "\(Int($0.rounded())) W" : nil
            } ?? "— W"
        case .ascent:
            let unit = measurementUnit ?? .meters
            let value = OverlayMeasurementFormatter.elevation(
                meters: sample?.ascentMeters,
                unit: unit
            ) ?? "—"
            return "\(value) \(unit == .feet ? "FT" : "M")"
        default:
            return ""
        }
    }
}
