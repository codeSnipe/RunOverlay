import Foundation

public enum ActivityParserError: LocalizedError {
    case unsupportedFileType
    case unreadableFile
    case emptyActivity
    case malformedGPX
    case malformedFIT(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            RunOverlayLocalization.text("error.unsupportedActivity")
        case .unreadableFile:
            RunOverlayLocalization.text("error.unreadableActivity")
        case .emptyActivity:
            RunOverlayLocalization.text("error.emptyActivity")
        case .malformedGPX:
            RunOverlayLocalization.text("error.malformedGpx")
        case let .malformedFIT(reason):
            String(
                format: RunOverlayLocalization.text("error.malformedFit"),
                locale: RunOverlayLocalization.locale,
                arguments: [reason]
            )
        }
    }
}

public struct ActivityParser: Sendable {
    public init() {}

    public func parse(from url: URL) throws -> ParsedActivity {
        guard let kind = ActivityFileKind(rawValue: url.pathExtension.lowercased()) else {
            throw ActivityParserError.unsupportedFileType
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ActivityParserError.unreadableFile
        }

        let rawSamples: [ActivitySample]
        switch kind {
        case .gpx:
            rawSamples = try GPXParser().parse(data)
        case .fit:
            rawSamples = try FITParser().parseActivity(data)
        }

        return try ActivityNormalizer().normalize(rawSamples, kind: kind)
    }
}
