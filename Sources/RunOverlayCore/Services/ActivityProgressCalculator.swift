import Foundation

public struct ActivityProgress: Equatable, Sendable {
    public let fraction: Double
    public let currentDistanceMeters: Double?
    public let totalDistanceMeters: Double?

    public init(
        fraction: Double,
        currentDistanceMeters: Double?,
        totalDistanceMeters: Double?
    ) {
        self.fraction = fraction
        self.currentDistanceMeters = currentDistanceMeters
        self.totalDistanceMeters = totalDistanceMeters
    }

    public var startLabel: String { "0km" }
    public var currentLabel: String { Self.label(for: currentDistanceMeters) }
    public var totalLabel: String { Self.label(for: totalDistanceMeters) }

    private static func label(for meters: Double?) -> String {
        guard let value = OverlayMeasurementFormatter.distance(
            meters: meters,
            unit: .kilometers
        ) else {
            return "— km"
        }
        return "\(value) km"
    }
}

/// 根据整段运动数据计算当前跑步进度，预览和导出共用同一套规则。
public struct ActivityProgressCalculator: Sendable {
    private struct DistancePoint: Sendable {
        let timestamp: Date
        let cumulativeMaximum: Double
    }

    private let startTime: Date?
    private let endTime: Date?
    private let startDistance: Double?
    private let endDistance: Double?
    private let distancePoints: [DistancePoint]

    public init(samples: [ActivitySample] = []) {
        let sortedSamples = samples.sorted { $0.timestamp < $1.timestamp }
        startTime = sortedSamples.first?.timestamp
        endTime = sortedSamples.last?.timestamp

        let validDistances = sortedSamples.compactMap { sample -> (Date, Double)? in
            guard let distance = sample.distanceMeters,
                  distance.isFinite,
                  distance >= 0 else {
                return nil
            }
            return (sample.timestamp, distance)
        }
        startDistance = validDistances.first?.1

        var maximumDistance = -Double.infinity
        var points: [DistancePoint] = []
        points.reserveCapacity(validDistances.count)
        for (timestamp, distance) in validDistances {
            maximumDistance = max(maximumDistance, distance)
            points.append(DistancePoint(
                timestamp: timestamp,
                cumulativeMaximum: maximumDistance
            ))
        }
        distancePoints = points
        endDistance = points.last?.cumulativeMaximum
    }

    public func progress(for sample: ActivitySample?) -> ActivityProgress? {
        guard let sample else {
            return nil
        }

        let totalDistance: Double?
        let currentDistance: Double?
        if let startDistance, let endDistance {
            let distance = max(0, endDistance - startDistance)
            totalDistance = distance
            if let cumulative = cumulativeDistance(at: sample.timestamp) {
                let sampleDistance = sample.distanceMeters.flatMap {
                    $0.isFinite && $0 >= 0 ? $0 : nil
                }
                currentDistance = min(
                    max(0, max(cumulative, sampleDistance ?? cumulative) - startDistance),
                    distance
                )
            } else {
                currentDistance = nil
            }
        } else {
            totalDistance = nil
            currentDistance = nil
        }

        let fraction: Double
        if let totalDistance, totalDistance > 0, let currentDistance {
            fraction = clamped(currentDistance / totalDistance)
        } else if let startTime, let endTime, endTime > startTime {
            fraction = clamped(
                sample.timestamp.timeIntervalSince(startTime) /
                    endTime.timeIntervalSince(startTime)
            )
        } else {
            fraction = 0
        }
        return ActivityProgress(
            fraction: fraction,
            currentDistanceMeters: currentDistance,
            totalDistanceMeters: totalDistance
        )
    }

    public func fraction(for sample: ActivitySample?) -> Double? {
        progress(for: sample)?.fraction
    }

    private func cumulativeDistance(at timestamp: Date) -> Double? {
        guard !distancePoints.isEmpty else {
            return nil
        }

        var lower = 0
        var upper = distancePoints.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if distancePoints[middle].timestamp <= timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower > 0 else {
            return startDistance
        }
        return distancePoints[lower - 1].cumulativeMaximum
    }

    private func clamped(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }
}
