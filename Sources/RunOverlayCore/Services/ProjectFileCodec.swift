import Foundation

public enum ProjectFileCodecError: LocalizedError {
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            String(
                format: RunOverlayLocalization.text("error.projectSchema"),
                locale: RunOverlayLocalization.locale,
                arguments: [version]
            )
        }
    }
}

public struct ProjectFileCodec: Sendable {
    public init() {}

    public func encode(_ project: RunOverlayProject) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(project)
    }

    public func decode(_ data: Data) throws -> RunOverlayProject {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let project = try decoder.decode(RunOverlayProject.self, from: data)

        guard project.schemaVersion <= RunOverlayProject.currentSchemaVersion else {
            throw ProjectFileCodecError.unsupportedSchema(project.schemaVersion)
        }
        return project
    }

    public func save(_ project: RunOverlayProject, to url: URL) throws {
        try encode(project).write(to: url, options: .atomic)
    }

    public func load(from url: URL) throws -> RunOverlayProject {
        try decode(Data(contentsOf: url))
    }
}
