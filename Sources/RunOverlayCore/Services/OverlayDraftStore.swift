import Foundation

public struct OverlayDraftStore {
    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "runoverlay.overlayDraftLibrary"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func load() throws -> OverlayDraftLibrary {
        guard let data = defaults.data(forKey: storageKey) else {
            return OverlayDraftLibrary()
        }
        return try JSONDecoder().decode(OverlayDraftLibrary.self, from: data)
    }

    public func save(_ library: OverlayDraftLibrary) throws {
        let data = try JSONEncoder().encode(library)
        defaults.set(data, forKey: storageKey)
    }
}
