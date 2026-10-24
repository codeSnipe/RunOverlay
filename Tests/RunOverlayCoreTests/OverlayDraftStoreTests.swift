import Foundation
import XCTest
@testable import RunOverlayCore

final class OverlayDraftStoreTests: XCTestCase {
    func test草稿完整保存并恢复默认配置() throws {
        let suiteName = "RunOverlayDraftTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = OverlayDraftStore(defaults: defaults)
        var configuration = OverlayConfiguration.preset(.technology)
        configuration.elements[0].frame.x = 0.37
        configuration.elements[0].opacity = 0.58
        configuration.elements[0].backgroundOpacity = 0.23
        var library = OverlayDraftLibrary()
        let first = OverlayDraft(name: "清晨", configuration: configuration)
        library.add(first, makeDefault: true)
        library.add(
            OverlayDraft(
                name: "夜跑",
                configuration: .preset(.minimal)
            ),
            makeDefault: false
        )

        try store.save(library)
        let restored = try store.load()

        XCTAssertEqual(restored, library)
        XCTAssertEqual(restored.defaultDraftID, first.id)
        XCTAssertEqual(restored.defaultConfiguration, configuration)
    }

    func test切换与删除默认草稿不会影响其他草稿() {
        let first = OverlayDraft(
            name: "第一版",
            configuration: .preset(.sport)
        )
        let second = OverlayDraft(
            name: "第二版",
            configuration: .preset(.technology)
        )
        var library = OverlayDraftLibrary()
        library.add(first, makeDefault: true)
        library.add(second, makeDefault: false)

        XCTAssertTrue(library.setDefault(second.id))
        XCTAssertEqual(library.defaultConfiguration, second.configuration)
        XCTAssertFalse(library.setDefault(UUID()))
        XCTAssertTrue(library.remove(second.id))
        XCTAssertNil(library.defaultDraftID)
        XCTAssertNil(library.defaultConfiguration)
        XCTAssertEqual(library.drafts, [first])
    }

    func test损坏的草稿数据会报错且不会被加载覆盖() throws {
        let suiteName = "RunOverlayDraftTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "test.overlayDraftLibrary"
        let invalidData = Data("无效草稿".utf8)
        defaults.set(invalidData, forKey: storageKey)
        let store = OverlayDraftStore(
            defaults: defaults,
            storageKey: storageKey
        )

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(defaults.data(forKey: storageKey), invalidData)
    }
}
