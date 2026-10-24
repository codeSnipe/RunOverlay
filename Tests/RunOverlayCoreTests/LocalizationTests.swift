import XCTest
@testable import RunOverlayCore

final class LocalizationTests: XCTestCase {
    func test缺失的应用菜单译文显示可读文案而不是键名() {
        XCTAssertEqual(
            RunOverlayLocalization.appText(
                "ui.project.package.missing-for-test",
                fallback: "打包项目与素材…"
            ),
            "打包项目与素材…"
        )
    }

    func test界面语言切换会更新核心模型显示名称() {
        let originalLanguage = RunOverlayLocalization.language
        defer {
            RunOverlayLocalization.language = originalLanguage
        }

        RunOverlayLocalization.language = .chineseSimplified
        XCTAssertEqual(ExportAspectRatio.portrait9x16.displayName, "竖屏 9:16")

        RunOverlayLocalization.language = .english
        XCTAssertEqual(ExportAspectRatio.portrait9x16.displayName, "Portrait 9:16")

        RunOverlayLocalization.language = .japanese
        XCTAssertEqual(ExportAspectRatio.portrait9x16.displayName, "縦 9:16")
    }
}
