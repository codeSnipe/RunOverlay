import Foundation

public struct ActivityTimeline: Sendable {
    public init() {}

    public func sample(
        at timestamp: Date,
        in samples: [ActivitySample],
        maximumGap: TimeInterval = 30
    ) -> ActivitySample? {
        guard let first = samples.first, let last = samples.last,
              timestamp >= first.timestamp, timestamp <= last.timestamp
        else {
            return nil
        }

        var lower = 0
        var upper = samples.count - 1
        while lower < upper {
            let middle = (lower + upper) / 2
            if samples[middle].timestamp < timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        let next = samples[lower]
        if next.timestamp == timestamp || lower == 0 {
            return next
        }

        let previous = samples[lower - 1]
        let interval = next.timestamp.timeIntervalSince(previous.timestamp)
        guard interval > 0, interval <= maximumGap else {
            return nil
        }
        let fraction = timestamp.timeIntervalSince(previous.timestamp) / interval

        return ActivitySample(
            timestamp: timestamp,
            coordinate: interpolate(previous.coordinate, next.coordinate, fraction),
            distanceMeters: interpolate(previous.distanceMeters, next.distanceMeters, fraction),
            speedMetersPerSecond: interpolate(
                previous.speedMetersPerSecond,
                next.speedMetersPerSecond,
                fraction
            ),
            heartRate: interpolate(previous.heartRate, next.heartRate, fraction),
            cadence: interpolate(previous.cadence, next.cadence, fraction),
            power: interpolate(previous.power, next.power, fraction),
            altitudeMeters: interpolate(previous.altitudeMeters, next.altitudeMeters, fraction),
            ascentMeters: interpolate(previous.ascentMeters, next.ascentMeters, fraction),
            caloriesKilocalories: interpolate(
                previous.caloriesKilocalories,
                next.caloriesKilocalories,
                fraction
            )
        )
    }

    public func smoothed(
        samples: [ActivitySample],
        level: SmoothingLevel
    ) -> [ActivitySample] {
        let window: TimeInterval
        switch level {
        case .off:
            return samples
        case .light:
            window = 3
        case .standard:
            window = 5
        case .strong:
            window = 10
        }

        var result = samples
        var start = 0
        var speedSum = 0.0
        var speedCount = 0

        for end in samples.indices {
            if let speed = samples[end].speedMetersPerSecond {
                speedSum += speed
                speedCount += 1
            }

            while samples[end].timestamp.timeIntervalSince(samples[start].timestamp) > window {
                if let speed = samples[start].speedMetersPerSecond {
                    speedSum -= speed
                    speedCount -= 1
                }
                start += 1
            }

            if speedCount > 0 {
                result[end].speedMetersPerSecond = speedSum / Double(speedCount)
            }
        }

        return result
    }

    private func interpolate(
        _ first: Double?,
        _ second: Double?,
        _ fraction: Double
    ) -> Double? {
        switch (first, second) {
        case let (.some(first), .some(second)):
            first + (second - first) * fraction
        case let (.some(first), .none):
            first
        case let (.none, .some(second)):
            second
        case (.none, .none):
            nil
        }
    }

    private func interpolate(
        _ first: GeoCoordinate?,
        _ second: GeoCoordinate?,
        _ fraction: Double
    ) -> GeoCoordinate? {
        guard let first, let second else {
            return first ?? second
        }
        return GeoCoordinate(
            latitude: first.latitude + (second.latitude - first.latitude) * fraction,
            longitude: first.longitude + (second.longitude - first.longitude) * fraction
        )
    }
}
