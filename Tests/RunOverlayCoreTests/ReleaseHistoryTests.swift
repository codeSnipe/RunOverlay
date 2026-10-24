import XCTest
@testable import RunOverlayCore

final class ReleaseHistoryTests: XCTestCase {
    func test已发布记录按版本倒序且构建号格式正确() {
        XCTAssertEqual(
            ReleaseHistory.published.map(\.build),
            [20, 19, 18, 17, 16, 15, 14, 13, 12]
        )
        XCTAssertEqual(
            ReleaseHistory.published.map { $0.version(base: "0.1.0") },
            ["0.1.0-020", "0.1.0-019", "0.1.0-018", "0.1.0-017",
             "0.1.0-016", "0.1.0-015", "0.1.0-014", "0.1.0-013",
             "0.1.0-012"]
        )
        XCTAssertTrue(ReleaseHistory.published.allSatisfy {
            !$0.titleKey.isEmpty && !$0.changeKeys.isEmpty
        })
    }

    func test查询安装包版本不会误将开发构建归入已发布版本() {
        XCTAssertEqual(
            ReleaseHistory.note(forVersion: "0.1.0-020", base: "0.1.0")?.build,
            20
        )
        XCTAssertNil(ReleaseHistory.note(forVersion: "0.1.0-001", base: "0.1.0"))
        XCTAssertNil(ReleaseHistory.note(forVersion: "0.1.0-021", base: "0.1.0"))
    }
}
