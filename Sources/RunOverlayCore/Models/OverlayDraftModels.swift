import Foundation

public struct OverlayDraft: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var configuration: OverlayConfiguration
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        configuration: OverlayConfiguration,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.configuration = configuration
        self.createdAt = createdAt
    }
}

public struct OverlayDraftTemplate: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var name: String
    public var configuration: OverlayConfiguration

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        name: String,
        configuration: OverlayConfiguration
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.configuration = configuration
    }
}

public enum OverlayDraftImportResult: Equatable, Sendable {
    case imported(OverlayDraft)
    case alreadyExists(OverlayDraft)
}

public struct OverlayDraftLibrary: Codable, Hashable, Sendable {
    public private(set) var drafts: [OverlayDraft]
    public private(set) var defaultDraftID: UUID?

    public init(drafts: [OverlayDraft] = [], defaultDraftID: UUID? = nil) {
        self.drafts = drafts
        self.defaultDraftID = defaultDraftID
    }

    public var defaultConfiguration: OverlayConfiguration? {
        drafts.first { $0.id == defaultDraftID }?.configuration
    }

    public func draft(withID id: UUID) -> OverlayDraft? {
        drafts.first { $0.id == id }
    }

    public mutating func add(_ draft: OverlayDraft, makeDefault: Bool) {
        drafts.insert(draft, at: 0)
        if makeDefault {
            defaultDraftID = draft.id
        }
    }

    @discardableResult
    public mutating func setDefault(_ id: UUID) -> Bool {
        guard draft(withID: id) != nil else {
            return false
        }
        defaultDraftID = id
        return true
    }

    @discardableResult
    public mutating func remove(_ id: UUID) -> Bool {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else {
            return false
        }
        drafts.remove(at: index)
        if defaultDraftID == id {
            defaultDraftID = nil
        }
        return true
    }
}
