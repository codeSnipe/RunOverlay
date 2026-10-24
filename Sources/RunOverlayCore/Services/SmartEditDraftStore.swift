import Foundation

public struct SmartEditDraftStore: Sendable {
    public let directoryURL: URL
    private let codec: SmartEditDraftCodec

    public init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL()
        codec = SmartEditDraftCodec()
    }

    public func loadAll() throws -> [SmartEditDraft] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return []
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension == "runoverlay-edit" }
            .compactMap { try? codec.load(from: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ draft: SmartEditDraft) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try codec.save(
            draft,
            to: directoryURL.appendingPathComponent("\(draft.id.uuidString).runoverlay-edit")
        )
    }

    public func delete(_ draft: SmartEditDraft) throws {
        let url = directoryURL.appendingPathComponent(
            "\(draft.id.uuidString).runoverlay-edit"
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func defaultDirectoryURL() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("RunOverlay/SmartEdit", isDirectory: true)
    }
}
