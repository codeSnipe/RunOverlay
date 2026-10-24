import Foundation

struct FITParser {
    private struct FieldDefinition {
        var number: UInt8
        var size: Int
        var baseType: UInt8
    }

    private struct MessageDefinition {
        var architecture: UInt8
        var globalMessageNumber: UInt16
        var fields: [FieldDefinition]
        var developerFieldSizes: [Int]
    }

    private struct Summary {
        var kind: UInt16
        var end: Date?
        var ascent: Double?
        var calories: Double?
    }

    private struct DataMessage {
        var sample: ActivitySample?
        var summary: Summary?
        var timestamp: UInt32?
    }

    private static let epoch = Date(timeIntervalSince1970: 631_065_600)

    func parse(_ data: Data) throws -> [ActivitySample] {
        try parseActivity(data)
    }

    func parseActivity(_ data: Data) throws -> [ActivitySample] {
        var reader = FITByteReader(data: data)
        let headerSize = Int(try reader.readUInt8())
        guard headerSize >= 12, data.count >= headerSize else {
            throw ActivityParserError.malformedFIT(
                RunOverlayLocalization.text("error.fit.invalidHeaderLength")
            )
        }

        _ = try reader.readUInt8()
        _ = try reader.readUInt16(littleEndian: true)
        let dataSize = Int(try reader.readUInt32(littleEndian: true))
        let signature = try reader.readBytes(count: 4)
        guard String(bytes: signature, encoding: .ascii) == ".FIT" else {
            throw ActivityParserError.malformedFIT(
                RunOverlayLocalization.text("error.fit.missingSignature")
            )
        }

        reader.offset = headerSize
        let dataEnd = headerSize + dataSize
        guard dataEnd <= data.count else {
            throw ActivityParserError.malformedFIT(
                RunOverlayLocalization.text("error.fit.dataOutOfBounds")
            )
        }

        var definitions: [UInt8: MessageDefinition] = [:]
        var samples: [ActivitySample] = []
        var summaries: [Summary] = []
        var lastTimestamp: UInt32?

        while reader.offset < dataEnd {
            let header = try reader.readUInt8()

            if header & 0x80 != 0 {
                let localMessage = (header >> 5) & 0x03
                let timeOffset = UInt32(header & 0x1F)
                guard let definition = definitions[localMessage] else {
                    throw ActivityParserError.malformedFIT(
                        RunOverlayLocalization.text("error.fit.missingCompressedDefinition")
                    )
                }
                let compressedTimestamp = expandedTimestamp(
                    previous: lastTimestamp,
                    offset: timeOffset
                )
                let message = try readDataMessage(
                    definition,
                    reader: &reader,
                    compressedTimestamp: compressedTimestamp
                )
                if let sample = message.sample {
                    samples.append(sample)
                }
                if let summary = message.summary { summaries.append(summary) }
                lastTimestamp = message.timestamp ?? lastTimestamp
                continue
            }

            let localMessage = header & 0x0F
            let isDefinition = header & 0x40 != 0
            let hasDeveloperFields = header & 0x20 != 0

            if isDefinition {
                definitions[localMessage] = try readDefinition(
                    reader: &reader,
                    hasDeveloperFields: hasDeveloperFields
                )
            } else {
                guard let definition = definitions[localMessage] else {
                    throw ActivityParserError.malformedFIT(
                        RunOverlayLocalization.text("error.fit.missingDefinition")
                    )
                }
                let message = try readDataMessage(
                    definition,
                    reader: &reader,
                    compressedTimestamp: nil
                )
                if let sample = message.sample {
                    samples.append(sample)
                }
                if let summary = message.summary { summaries.append(summary) }
                lastTimestamp = message.timestamp ?? lastTimestamp
            }
        }

        applySummaries(summaries, to: &samples)
        return samples
    }

    private func readDefinition(
        reader: inout FITByteReader,
        hasDeveloperFields: Bool
    ) throws -> MessageDefinition {
        _ = try reader.readUInt8()
        let architecture = try reader.readUInt8()
        let littleEndian = architecture == 0
        let globalMessageNumber = try reader.readUInt16(littleEndian: littleEndian)
        let fieldCount = Int(try reader.readUInt8())
        var fields: [FieldDefinition] = []

        for _ in 0..<fieldCount {
            fields.append(
                FieldDefinition(
                    number: try reader.readUInt8(),
                    size: Int(try reader.readUInt8()),
                    baseType: try reader.readUInt8()
                )
            )
        }

        var developerFieldSizes: [Int] = []
        if hasDeveloperFields {
            let developerFieldCount = Int(try reader.readUInt8())
            for _ in 0..<developerFieldCount {
                _ = try reader.readUInt8()
                developerFieldSizes.append(Int(try reader.readUInt8()))
                _ = try reader.readUInt8()
            }
        }

        return MessageDefinition(
            architecture: architecture,
            globalMessageNumber: globalMessageNumber,
            fields: fields,
            developerFieldSizes: developerFieldSizes
        )
    }

    private func readDataMessage(
        _ definition: MessageDefinition,
        reader: inout FITByteReader,
        compressedTimestamp: UInt32?
    ) throws -> DataMessage {
        let littleEndian = definition.architecture == 0
        var timestamp = compressedTimestamp
        var latitude: Int32?
        var longitude: Int32?
        var distance: UInt32?
        var speed: UInt32?
        var heartRate: UInt8?
        var cadence: UInt8?
        var power: UInt16?
        var altitude: UInt32?
        var calories: UInt64?
        var ascent: UInt64?

        for field in definition.fields {
            let bytes = try reader.readBytes(count: field.size)
            guard [18, 19, 20].contains(definition.globalMessageNumber) else {
                continue
            }

            switch field.number {
            case 253:
                timestamp = unsignedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                ).flatMap(UInt32.init(exactly:))
            case 0:
                guard definition.globalMessageNumber == 20 else { break }
                latitude = signedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                ).map(Int32.init)
            case 1:
                guard definition.globalMessageNumber == 20 else { break }
                longitude = signedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                ).map(Int32.init)
            case 5:
                guard definition.globalMessageNumber == 20 else { break }
                distance = unsignedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                ).map(UInt32.init)
            case 6:
                guard definition.globalMessageNumber == 20 else { break }
                speed = unsignedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                ).map(UInt32.init)
            case 3:
                guard definition.globalMessageNumber == 20 else { break }
                heartRate = unsignedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                ).map(UInt8.init)
            case 4:
                guard definition.globalMessageNumber == 20 else { break }
                cadence = unsignedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                ).map(UInt8.init)
            case 7:
                guard definition.globalMessageNumber == 20 else { break }
                power = unsignedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                ).map(UInt16.init)
            case 2:
                guard definition.globalMessageNumber == 20 else { break }
                altitude = unsignedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                ).map(UInt32.init)
            case 73:
                guard definition.globalMessageNumber == 20 else { break }
                speed = unsignedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                ).map(UInt32.init)
            case 78:
                guard definition.globalMessageNumber == 20 else { break }
                altitude = unsignedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                ).map(UInt32.init)
            case 11:
                guard definition.globalMessageNumber == 18 ||
                      definition.globalMessageNumber == 19 else { break }
                calories = unsignedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                )
            case 21:
                guard definition.globalMessageNumber == 19 else { break }
                ascent = unsignedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                )
            case 22:
                guard definition.globalMessageNumber == 18 else { break }
                ascent = unsignedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                )
            case 33:
                guard definition.globalMessageNumber == 20 else { break }
                calories = unsignedValue(
                    bytes,
                    baseType: field.baseType,
                    littleEndian: littleEndian
                )
            default:
                break
            }
        }

        for size in definition.developerFieldSizes {
            _ = try reader.readBytes(count: size)
        }

        guard definition.globalMessageNumber == 20, let timestamp else {
            let summary: Summary?
            if definition.globalMessageNumber == 18 || definition.globalMessageNumber == 19 {
                summary = Summary(
                    kind: definition.globalMessageNumber,
                    end: timestamp.map { Self.epoch.addingTimeInterval(TimeInterval($0)) },
                    ascent: ascent.map { Double($0) },
                    calories: calories.map { Double($0) }
                )
            } else {
                summary = nil
            }
            return DataMessage(sample: nil, summary: summary, timestamp: timestamp)
        }

        let coordinate: GeoCoordinate?
        if let latitude, let longitude {
            let factor = 180.0 / 2_147_483_648.0
            coordinate = GeoCoordinate(
                latitude: Double(latitude) * factor,
                longitude: Double(longitude) * factor
            )
        } else {
            coordinate = nil
        }

        let sample = ActivitySample(
            timestamp: Self.epoch.addingTimeInterval(TimeInterval(timestamp)),
            coordinate: coordinate,
            distanceMeters: distance.map { Double($0) / 100 },
            speedMetersPerSecond: speed.map { Double($0) / 1_000 },
            heartRate: heartRate.map(Double.init),
            cadence: cadence.map(Double.init),
            power: power.map(Double.init),
            altitudeMeters: altitude.map { Double($0) / 5 - 500 },
            caloriesKilocalories: calories.map { Double($0) }
        )
        return DataMessage(sample: sample, summary: nil, timestamp: timestamp)
    }

    private func applySummaries(_ summaries: [Summary], to samples: inout [ActivitySample]) {
        guard !samples.isEmpty else { return }
        samples.sort { $0.timestamp < $1.timestamp }
        let ascents = ActivityNormalizer.cumulativeAscent(in: samples)

        for metric in [Metric.ascent, .calories] {
            var anchors: [(index: Int, value: Double)] = [(0, 0)]
            var lapTotal = 0.0
            let laps = summaries.filter { $0.kind == 19 }.sorted {
                ($0.end ?? .distantFuture) < ($1.end ?? .distantFuture)
            }
            for lap in laps {
                guard let value = metric.value(in: lap), value.isFinite,
                      value >= 0, let end = lap.end else { continue }
                lapTotal += value
                anchors.append((sampleIndex(at: end, in: samples), lapTotal))
            }

            if let session = summaries.last(where: { $0.kind == 18 }),
               let total = metric.value(in: session), total.isFinite, total >= 0 {
                anchors.append((samples.count - 1, total))
            }

            guard anchors.count > 1 else { continue }
            anchors.sort {
                $0.index == $1.index ? $0.value < $1.value : $0.index < $1.index
            }
            var start = anchors[0]
            for anchor in anchors.dropFirst() {
                guard anchor.index >= start.index else { continue }
                let target = max(start.value, anchor.value)
                let timeSpan = samples[anchor.index].timestamp.timeIntervalSince(
                    samples[start.index].timestamp
                )
                let ascentSpan: Double
                if let ascents {
                    ascentSpan = ascents[anchor.index] - ascents[start.index]
                } else {
                    ascentSpan = 0
                }

                for index in start.index...anchor.index {
                    let fraction: Double
                    if metric == .ascent && ascentSpan > 0, let ascents {
                        fraction = (ascents[index] - ascents[start.index]) / ascentSpan
                    } else if timeSpan > 0 {
                        fraction = samples[index].timestamp.timeIntervalSince(
                            samples[start.index].timestamp
                        ) / timeSpan
                    } else {
                        fraction = index == anchor.index ? 1 : 0
                    }
                    metric.set(
                        start.value + (target - start.value) * fraction,
                        on: &samples[index],
                        isSummaryBoundary: index == anchor.index
                    )
                }
                start = (anchor.index, target)
            }
            for index in samples.indices where index > start.index {
                metric.set(start.value, on: &samples[index])
            }
        }
    }

    private enum Metric {
        case ascent
        case calories

        func value(in summary: Summary) -> Double? {
            switch self {
            case .ascent: summary.ascent
            case .calories: summary.calories
            }
        }

        func set(
            _ value: Double,
            on sample: inout ActivitySample,
            isSummaryBoundary: Bool = false
        ) {
            switch self {
            case .ascent: sample.ascentMeters = value
            case .calories:
                if sample.caloriesKilocalories == nil || isSummaryBoundary {
                    sample.caloriesKilocalories = value
                }
            }
        }
    }

    private func sampleIndex(at end: Date, in samples: [ActivitySample]) -> Int {
        samples.firstIndex(where: { $0.timestamp >= end }) ?? samples.count - 1
    }

    private func expandedTimestamp(previous: UInt32?, offset: UInt32) -> UInt32? {
        guard let previous else {
            return nil
        }
        var candidate = (previous & ~0x1F) | offset
        if candidate < previous {
            candidate += 0x20
        }
        return candidate
    }

    private func unsignedValue(
        _ bytes: [UInt8],
        baseType: UInt8,
        littleEndian: Bool
    ) -> UInt64? {
        let value = integer(bytes, littleEndian: littleEndian)
        let type = baseType & 0x1F
        let invalid: UInt64
        switch type {
        case 0, 2, 13: invalid = 0xFF
        case 4: invalid = 0xFFFF
        case 6: invalid = 0xFFFF_FFFF
        case 10, 11, 12, 16: invalid = 0
        default: invalid = UInt64.max
        }
        return value == invalid ? nil : value
    }

    private func signedValue(
        _ bytes: [UInt8],
        baseType: UInt8,
        littleEndian: Bool
    ) -> Int64? {
        let raw = integer(bytes, littleEndian: littleEndian)
        let type = baseType & 0x1F
        switch type {
        case 1:
            let value = Int8(bitPattern: UInt8(truncatingIfNeeded: raw))
            return value == .max ? nil : Int64(value)
        case 3:
            let value = Int16(bitPattern: UInt16(truncatingIfNeeded: raw))
            return value == .max ? nil : Int64(value)
        case 5:
            let value = Int32(bitPattern: UInt32(truncatingIfNeeded: raw))
            return value == .max ? nil : Int64(value)
        default:
            return Int64(raw)
        }
    }

    private func integer(_ bytes: [UInt8], littleEndian: Bool) -> UInt64 {
        if littleEndian {
            return bytes.reversed().reduce(0) { ($0 << 8) | UInt64($1) }
        }
        return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}

private struct FITByteReader {
    let data: Data
    var offset = 0

    mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else {
            throw ActivityParserError.malformedFIT(
                RunOverlayLocalization.text("error.fit.unexpectedEnd")
            )
        }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16(littleEndian: Bool) throws -> UInt16 {
        UInt16(try readInteger(count: 2, littleEndian: littleEndian))
    }

    mutating func readUInt32(littleEndian: Bool) throws -> UInt32 {
        UInt32(try readInteger(count: 4, littleEndian: littleEndian))
    }

    mutating func readBytes(count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= data.count else {
            throw ActivityParserError.malformedFIT(
                RunOverlayLocalization.text("error.fit.fieldOutOfBounds")
            )
        }
        defer { offset += count }
        return Array(data[offset..<(offset + count)])
    }

    private mutating func readInteger(
        count: Int,
        littleEndian: Bool
    ) throws -> UInt64 {
        let bytes = try readBytes(count: count)
        if littleEndian {
            return bytes.reversed().reduce(0) { ($0 << 8) | UInt64($1) }
        }
        return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}
