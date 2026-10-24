import Foundation

public enum OverlayMeasurementFormatter {
    public static func pace(
        speedMetersPerSecond: Double?,
        unit: OverlayMeasurementUnit
    ) -> (minutes: Int, seconds: Int)? {
        guard let speedMetersPerSecond,
              speedMetersPerSecond.isFinite,
              speedMetersPerSecond > 0.05,
              unit == .kilometers || unit == .miles else {
            return nil
        }
        let totalSeconds = Int(
            (unit.metersPerUnit / speedMetersPerSecond).rounded()
        )
        return (totalSeconds / 60, totalSeconds % 60)
    }

    public static func distance(
        meters: Double?,
        unit: OverlayMeasurementUnit
    ) -> String? {
        guard let meters, meters.isFinite,
              unit == .kilometers || unit == .miles else {
            return nil
        }
        return String(format: "%.2f", meters / unit.metersPerUnit)
    }

    public static func elevation(
        meters: Double?,
        unit: OverlayMeasurementUnit
    ) -> String? {
        guard let meters, meters.isFinite,
              unit == .meters || unit == .feet else {
            return nil
        }
        return String(Int((meters / unit.metersPerUnit).rounded()))
    }
}
