import Foundation

public struct ActivityNormalizer: Sendable {
    public init() {}

    public func normalize(
        _ rawSamples: [ActivitySample],
        kind: ActivityFileKind
    ) throws -> ParsedActivity {
        let sorted = rawSamples
            .filter { $0.timestamp.timeIntervalSince1970.isFinite }
            .sorted { $0.timestamp < $1.timestamp }

        guard !sorted.isEmpty else {
            throw ActivityParserError.emptyActivity
        }

        var samples: [ActivitySample] = []
        for sample in sorted {
            if let last = samples.last, last.timestamp == sample.timestamp {
                samples[samples.count - 1] = merge(last, sample)
            } else {
                samples.append(sample)
            }
        }

        fillDerivedDistanceAndSpeed(in: &samples)
        fillDerivedAscent(in: &samples)
        fillMissingCumulativeCalories(in: &samples)

        guard let first = samples.first, let last = samples.last else {
            throw ActivityParserError.emptyActivity
        }

        return ParsedActivity(
            kind: kind,
            samples: samples,
            timeRange: DateInterval(start: first.timestamp, end: last.timestamp),
            availableChannels: availableChannels(in: samples)
        )
    }

    private func merge(
        _ first: ActivitySample,
        _ second: ActivitySample
    ) -> ActivitySample {
        ActivitySample(
            timestamp: first.timestamp,
            coordinate: second.coordinate ?? first.coordinate,
            distanceMeters: second.distanceMeters ?? first.distanceMeters,
            speedMetersPerSecond: second.speedMetersPerSecond ?? first.speedMetersPerSecond,
            heartRate: second.heartRate ?? first.heartRate,
            cadence: second.cadence ?? first.cadence,
            power: second.power ?? first.power,
            altitudeMeters: second.altitudeMeters ?? first.altitudeMeters,
            ascentMeters: second.ascentMeters ?? first.ascentMeters,
            caloriesKilocalories: second.caloriesKilocalories ?? first.caloriesKilocalories
        )
    }

    private func fillDerivedAscent(in samples: inout [ActivitySample]) {
        let derived = Self.cumulativeAscent(in: samples)
        guard let derived else {
            return
        }

        for index in samples.indices where samples[index].ascentMeters == nil {
            samples[index].ascentMeters = derived[index]
        }
    }

    // 高程先用相邻三点中值滤掉孤立尖峰，再以 3 米回落/爬升门槛抑制 GPS 抖动。
    static func cumulativeAscent(in samples: [ActivitySample]) -> [Double]? {
        let altitudes = samples.map { sample -> Double? in
            guard let altitude = sample.altitudeMeters,
                  altitude.isFinite,
                  (-500...9_000).contains(altitude)
            else {
                return nil
            }
            return altitude
        }
        guard altitudes.contains(where: { $0 != nil }) else {
            return nil
        }

        var filtered = altitudes
        for index in samples.indices.dropFirst() where index + 1 < samples.count {
            guard let before = altitudes[index - 1],
                  let current = altitudes[index],
                  let after = altitudes[index + 1],
                  samples[index].timestamp.timeIntervalSince(samples[index - 1].timestamp) <= 30,
                  samples[index + 1].timestamp.timeIntervalSince(samples[index].timestamp) <= 30
            else {
                continue
            }
            filtered[index] = [before, current, after].sorted()[1]
        }

        var result = Array(repeating: 0.0, count: samples.count)
        var base: Double?
        var peak: Double?
        var previousIndex: Int?
        var committed = 0.0

        for index in samples.indices {
            guard let altitude = filtered[index] else {
                result[index] = committed
                continue
            }

            if let previousIndex, let previous = filtered[previousIndex] {
                let interval = samples[index].timestamp.timeIntervalSince(
                    samples[previousIndex].timestamp
                )
                // 超长断点或明显不可信的垂直跃迁不能计作一次爬升。
                if interval > 120 || abs(altitude - previous) > max(6, interval * 3 + 3) {
                    committed += max(0, result[previousIndex] - committed)
                    base = nil
                    peak = nil
                }
            }

            if base == nil {
                base = altitude
                peak = altitude
            } else if let currentPeak = peak, let currentBase = base {
                if altitude > currentPeak {
                    peak = altitude
                } else if currentPeak - altitude >= 3 {
                    committed += max(0, currentPeak - currentBase)
                    base = altitude
                    peak = altitude
                } else if altitude < currentBase {
                    base = altitude
                }
            }

            let pending = max(0, (peak ?? altitude) - (base ?? altitude))
            result[index] = committed + (pending >= 3 ? pending : 0)
            previousIndex = index
        }

        return result
    }

    private func fillMissingCumulativeCalories(in samples: inout [ActivitySample]) {
        var anchors: [(index: Int, value: Double)] = []
        for index in samples.indices {
            guard let calories = samples[index].caloriesKilocalories,
                  calories.isFinite, calories >= 0
            else {
                samples[index].caloriesKilocalories = nil
                continue
            }
            let previous = anchors.last?.value ?? 0
            anchors.append((index, max(previous, calories)))
        }
        guard !anchors.isEmpty else {
            return
        }

        if anchors[0].index > 0 {
            anchors.insert((0, 0), at: 0)
        }
        for (start, end) in zip(anchors, anchors.dropFirst()) {
            let duration = samples[end.index].timestamp.timeIntervalSince(
                samples[start.index].timestamp
            )
            for index in start.index...end.index {
                let fraction = duration > 0
                    ? samples[index].timestamp.timeIntervalSince(
                        samples[start.index].timestamp
                    ) / duration
                    : 1
                samples[index].caloriesKilocalories = start.value +
                    (end.value - start.value) * fraction
            }
        }
        if let last = anchors.last {
            for index in samples.indices where index > last.index {
                samples[index].caloriesKilocalories = last.value
            }
        }
    }

    private func fillDerivedDistanceAndSpeed(in samples: inout [ActivitySample]) {
        guard !samples.isEmpty else {
            return
        }

        var cumulativeDistance = samples[0].distanceMeters ?? 0
        if samples[0].distanceMeters == nil {
            samples[0].distanceMeters = cumulativeDistance
        }

        for index in samples.indices.dropFirst() {
            let previous = samples[index - 1]
            let interval = samples[index].timestamp.timeIntervalSince(previous.timestamp)
            let routeDelta = distance(
                from: previous.coordinate,
                to: samples[index].coordinate
            )

            if let sourceDistance = samples[index].distanceMeters {
                cumulativeDistance = max(cumulativeDistance, sourceDistance)
            } else {
                cumulativeDistance += routeDelta ?? 0
                samples[index].distanceMeters = cumulativeDistance
            }

            if samples[index].speedMetersPerSecond == nil,
               interval > 0,
               interval <= 30 {
                let distanceDelta: Double
                if let currentDistance = samples[index].distanceMeters,
                   let previousDistance = previous.distanceMeters {
                    distanceDelta = max(0, currentDistance - previousDistance)
                } else {
                    distanceDelta = routeDelta ?? 0
                }
                samples[index].speedMetersPerSecond = distanceDelta / interval
            }
        }
    }

    private func distance(
        from first: GeoCoordinate?,
        to second: GeoCoordinate?
    ) -> Double? {
        guard let first, let second else {
            return nil
        }

        let earthRadius = 6_371_000.0
        let latitude1 = first.latitude * .pi / 180
        let latitude2 = second.latitude * .pi / 180
        let latitudeDelta = (second.latitude - first.latitude) * .pi / 180
        let longitudeDelta = (second.longitude - first.longitude) * .pi / 180
        let haversine =
            sin(latitudeDelta / 2) * sin(latitudeDelta / 2) +
            cos(latitude1) * cos(latitude2) *
            sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return earthRadius * 2 * atan2(sqrt(haversine), sqrt(1 - haversine))
    }

    private func availableChannels(
        in samples: [ActivitySample]
    ) -> Set<ActivityDataChannel> {
        var channels: Set<ActivityDataChannel> = []
        for sample in samples {
            if sample.coordinate != nil { channels.insert(.location) }
            if sample.distanceMeters != nil { channels.insert(.distance) }
            if sample.speedMetersPerSecond != nil { channels.insert(.speed) }
            if sample.heartRate != nil { channels.insert(.heartRate) }
            if sample.cadence != nil { channels.insert(.cadence) }
            if sample.power != nil { channels.insert(.power) }
            if sample.altitudeMeters != nil { channels.insert(.altitude) }
            if sample.ascentMeters != nil { channels.insert(.ascent) }
            if sample.caloriesKilocalories != nil { channels.insert(.calories) }
        }
        return channels
    }
}
