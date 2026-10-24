import CoreGraphics
import Foundation

public struct ElevationProfilePoint: Equatable, Sendable {
    public let distanceFraction: Double
    public let elevationFraction: Double
    public let startsNewSegment: Bool

    public init(
        distanceFraction: Double,
        elevationFraction: Double,
        startsNewSegment: Bool = false
    ) {
        self.distanceFraction = distanceFraction
        self.elevationFraction = elevationFraction
        self.startsNewSegment = startsNewSegment
    }
}

/// 按整段运动距离生成海拔曲线，预览、截图和导出共用同一组采样点。
public struct ElevationProfile: Equatable, Sendable {
    public let points: [ElevationProfilePoint]
    public let startDistanceMeters: Double
    public let totalDistanceMeters: Double
    public let minimumAltitudeMeters: Double
    public let maximumAltitudeMeters: Double

    public init(samples: [ActivitySample] = []) {
        struct Reading {
            let time: Date
            let distance: Double
            let altitude: Double
            let startsNewSegment: Bool
        }

        var readings: [Reading] = []
        var previous: Reading?
        for sample in samples {
            guard let distance = sample.distanceMeters, distance.isFinite, distance >= 0,
                  let altitude = sample.altitudeMeters, altitude.isFinite,
                  (-500...9_000).contains(altitude) else {
                previous = nil
                continue
            }
            let startsNewSegment = previous.map {
                let gap = sample.timestamp.timeIntervalSince($0.time)
                return gap <= 0 || gap > 120 || distance < $0.distance ||
                    distance - $0.distance > 500
            } ?? !readings.isEmpty
            let reading = Reading(
                time: sample.timestamp,
                distance: distance,
                altitude: altitude,
                startsNewSegment: startsNewSegment
            )
            readings.append(reading)
            previous = reading
        }

        guard let first = readings.first, let last = readings.last,
              readings.count >= 2, last.distance > first.distance else {
            points = []
            startDistanceMeters = 0
            totalDistanceMeters = 0
            minimumAltitudeMeters = 0
            maximumAltitudeMeters = 0
            return
        }

        startDistanceMeters = first.distance
        totalDistanceMeters = last.distance - first.distance
        minimumAltitudeMeters = readings.map(\.altitude).min() ?? first.altitude
        maximumAltitudeMeters = readings.map(\.altitude).max() ?? first.altitude
        let center = (minimumAltitudeMeters + maximumAltitudeMeters) / 2
        let range = max(maximumAltitudeMeters - minimumAltitudeMeters, 10)
        let lower = center - range * 0.57
        let upper = center + range * 0.57
        let distanceSpan = last.distance - first.distance

        // 每段保留首尾及各采样桶的波峰/波谷，避免缩略时把爬坡压平。
        let bucketSize = max(1, Int(ceil(Double(readings.count) / 240)))
        var selectedIndices: Set<Int> = [0, readings.count - 1]
        for index in readings.indices where readings[index].startsNewSegment {
            selectedIndices.insert(index)
            if index > 0 { selectedIndices.insert(index - 1) }
        }
        for start in stride(from: 0, to: readings.count, by: bucketSize) {
            let end = min(start + bucketSize, readings.count)
            let indices = start..<end
            selectedIndices.insert(start)
            selectedIndices.insert(end - 1)
            if let low = indices.min(by: { readings[$0].altitude < readings[$1].altitude }),
               let high = indices.max(by: { readings[$0].altitude < readings[$1].altitude }) {
                selectedIndices.insert(low)
                selectedIndices.insert(high)
            }
        }
        var previousSelected = -1
        points = selectedIndices.sorted().map { index in
            let reading = readings[index]
            let startsNewSegment = readings[(previousSelected + 1)...index]
                .contains(where: \.startsNewSegment)
            previousSelected = index
            return ElevationProfilePoint(
                distanceFraction: min(max(
                    (reading.distance - first.distance) / distanceSpan, 0
                ), 1),
                elevationFraction: min(max(
                    (reading.altitude - lower) / (upper - lower), 0
                ), 1),
                startsNewSegment: startsNewSegment
            )
        }
    }

    public var isAvailable: Bool { points.count > 1 }

    public var distanceLabels: (start: String, end: String) {
        guard isAvailable else { return ("0 km", "— km") }
        return ("0 km", String(format: "%.1f km", totalDistanceMeters / 1_000))
    }

    public func marker(
        for sample: ActivitySample?,
        in rect: CGRect,
        originAtTop: Bool
    ) -> CGPoint? {
        guard isAvailable,
              let distance = sample?.distanceMeters, distance.isFinite,
              let altitude = sample?.altitudeMeters, altitude.isFinite,
              distance >= startDistanceMeters,
              distance <= startDistanceMeters + totalDistanceMeters else {
            return nil
        }
        let center = (minimumAltitudeMeters + maximumAltitudeMeters) / 2
        let range = max(maximumAltitudeMeters - minimumAltitudeMeters, 10)
        let lower = center - range * 0.57
        return position(
            distanceFraction: (distance - startDistanceMeters) / totalDistanceMeters,
            elevationFraction: min(max((altitude - lower) / (range * 1.14), 0), 1),
            in: rect,
            originAtTop: originAtTop
        )
    }

    public func position(
        for point: ElevationProfilePoint,
        in rect: CGRect,
        originAtTop: Bool
    ) -> CGPoint {
        position(
            distanceFraction: point.distanceFraction,
            elevationFraction: point.elevationFraction,
            in: rect,
            originAtTop: originAtTop
        )
    }

    private func position(
        distanceFraction: Double,
        elevationFraction: Double,
        in rect: CGRect,
        originAtTop: Bool
    ) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * distanceFraction,
            y: originAtTop
                ? rect.maxY - rect.height * elevationFraction
                : rect.minY + rect.height * elevationFraction
        )
    }

    public static func plotRect(in rect: CGRect, originAtTop: Bool) -> CGRect {
        CGRect(
            x: rect.minX + rect.width * 0.07,
            y: rect.minY + rect.height * (originAtTop ? 0.29 : 0.18),
            width: rect.width * 0.86,
            height: rect.height * 0.53
        )
    }
}
