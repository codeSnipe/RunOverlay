import XCTest
@testable import RunOverlayCore

final class CoverFontCatalogTests: XCTestCase {
    func test中文字体使用字形覆盖筛选而不是英文名称猜测() {
        XCTAssertTrue(CoverFontCatalog.supportsChinese("PingFangSC-Regular"))
        XCTAssertFalse(CoverFontCatalog.supportsChinese("HelveticaNeue"))
    }

    func test内置字体中文名称与原始字体名保持独立() {
        XCTAssertEqual(
            CoverFontCatalog.displayName(for: "ZhiMangXing-Regular"),
            "钟齐志莽行书"
        )
        XCTAssertEqual(
            CoverFontCatalog.displayName(for: "MaShanZheng-Regular"),
            "马善政毛笔字"
        )
        XCTAssertEqual(
            CoverFontCatalog.displayName(for: "ZCOOLKuaiLe-Regular"),
            "站酷快乐体"
        )
        XCTAssertEqual(
            CoverFontCatalog.displayName(for: "ZCOOLXiaoWei-Regular"),
            "站酷小薇体"
        )
        XCTAssertTrue(
            CoverFontCatalog.displayName(for: "PingFangSC-Regular")
                .contains("苹方")
        )
    }

    func test排序去重并把中文字体排在其他字体之前() {
        let names = CoverFontCatalog.orderedFontNames([
            "HelveticaNeue", "PingFangSC-Regular",
            "MaShanZheng-Regular", "PingFangSC-Regular"
        ])
        XCTAssertEqual(
            names,
            ["MaShanZheng-Regular", "PingFangSC-Regular", "HelveticaNeue"]
        )
    }

    func test行书字体位于内置中文字体前列() {
        let names = CoverFontCatalog.orderedFontNames([
            "HelveticaNeue",
            "PingFangSC-Regular",
            "MaShanZheng-Regular",
            "ZhiMangXing-Regular"
        ])
        XCTAssertEqual(
            names,
            [
                "ZhiMangXing-Regular",
                "MaShanZheng-Regular",
                "PingFangSC-Regular",
                "HelveticaNeue"
            ]
        )
    }
}
