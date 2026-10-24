import Foundation

struct GPXParser {
    func parse(_ data: Data) throws -> [ActivitySample] {
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw parser.parserError ?? ActivityParserError.malformedGPX
        }
        return delegate.normalizedSamples
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    private struct Point {
        var latitude: Double
        var longitude: Double
        var timestamp: Date?
        var elevation: Double?
        var speed: Double?
        var heartRate: Double?
        var cadence: Double?
        var power: Double?
        var calories: Double?
    }

    private var currentPoint: Point?
    private var elements: [String] = []
    private var textBuffer = ""
    private(set) var samples: [ActivitySample] = []
    private var trackCalories: Double?

    var normalizedSamples: [ActivitySample] {
        var result = samples
        if let trackCalories, !result.isEmpty {
            result[result.count - 1].caloriesKilocalories = trackCalories
        }
        return result
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(qName ?? elementName)
        elements.append(name)
        textBuffer = ""

        guard name == "trkpt",
              let latitudeText = attributeDict["lat"],
              let longitudeText = attributeDict["lon"],
              let latitude = Double(latitudeText),
              let longitude = Double(longitudeText)
        else {
            return
        }

        currentPoint = Point(latitude: latitude, longitude: longitude)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(qName ?? elementName)
        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            if !elements.isEmpty { elements.removeLast() }
            textBuffer = ""
        }
        guard currentPoint != nil else {
            if ["calories", "totalcalories", "total_calories"].contains(name),
               elements.contains("extensions"),
               let calories = Double(value), calories.isFinite, calories >= 0 {
                trackCalories = calories
            }
            return
        }

        switch name {
        case "time":
            currentPoint?.timestamp = ActivityDateParser.date(from: value)
        case "ele":
            currentPoint?.elevation = Double(value)
        case "speed":
            currentPoint?.speed = Double(value)
        case "hr":
            currentPoint?.heartRate = Double(value)
        case "cad":
            currentPoint?.cadence = Double(value)
        case "power", "watts":
            currentPoint?.power = Double(value)
        case "calories", "totalcalories", "total_calories":
            currentPoint?.calories = Double(value)
        case "trkpt":
            if let point = currentPoint, let timestamp = point.timestamp {
                samples.append(
                    ActivitySample(
                        timestamp: timestamp,
                        coordinate: GeoCoordinate(
                            latitude: point.latitude,
                            longitude: point.longitude
                        ),
                        speedMetersPerSecond: point.speed,
                        heartRate: point.heartRate,
                        cadence: point.cadence,
                        power: point.power,
                        altitudeMeters: point.elevation,
                        caloriesKilocalories: point.calories
                    )
                )
            }
            currentPoint = nil
        default:
            break
        }

    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
    }
}

private enum ActivityDateParser {
    static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
