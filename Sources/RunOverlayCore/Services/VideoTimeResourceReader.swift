import Foundation

public struct VideoTimeResourceReader: Sendable {
    public static let supportedExtensions: Set<String> = ["lrv", "lrf"]

    public init() {}

    public func capturedAt(from sidecarURL: URL) -> Date? {
        let stem = sidecarURL.deletingPathExtension().lastPathComponent
        let text: String
        let dateFormat: String
        let insta360Pattern = #"^(?:LRV|VID)_(\d{8})_(\d{6})_(\d{3})$"#
        let djiPattern = #"^DJI_(\d{8})(\d{6})_\d{4}_[A-Z0-9]+$"#
        if let match = matches(insta360Pattern, in: stem),
           let date = capture(1, in: stem, match: match),
           let time = capture(2, in: stem, match: match),
           let fraction = capture(3, in: stem, match: match) {
            text = "\(date) \(time).\(fraction)"
            dateFormat = "yyyyMMdd HHmmss.SSS"
        } else if let match = matches(djiPattern, in: stem),
                  let date = capture(1, in: stem, match: match),
                  let time = capture(2, in: stem, match: match) {
            text = "\(date) \(time)"
            dateFormat = "yyyyMMdd HHmmss"
        } else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.isLenient = false
        formatter.dateFormat = dateFormat
        return formatter.date(from: text)
    }

    public func candidateFileNames(forVideoName videoName: String) -> [String] {
        let stem = URL(fileURLWithPath: videoName)
            .deletingPathExtension().lastPathComponent
        var stems = [stem.lowercased()]
        let pattern = #"^VID_(\d{8}_\d{6}_\d{3})$"#
        if let match = matches(pattern, in: stem),
           let timestamp = capture(1, in: stem, match: match) {
            stems.append("lrv_\(timestamp.lowercased())")
        }
        return stems.flatMap { stem in
            Self.supportedExtensions.sorted().map { "\(stem).\($0)" }
        }
    }

    private func matches(_ pattern: String, in stem: String) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        return expression.firstMatch(
            in: stem,
            range: NSRange(stem.startIndex..., in: stem)
        )
    }

    private func capture(
        _ index: Int,
        in stem: String,
        match: NSTextCheckingResult
    ) -> String? {
        Range(match.range(at: index), in: stem).map { String(stem[$0]) }
    }
}
