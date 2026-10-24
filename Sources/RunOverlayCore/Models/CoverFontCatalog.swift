import CoreGraphics
import CoreText
import Foundation

/// 封面编辑器的字体分类与中文名称，字体实际存储名始终保持 PostScript 名称。
public enum CoverFontCatalog {
    public static let featuredChineseFonts = [
        "ZhiMangXing-Regular",
        "MaShanZheng-Regular",
        "ZCOOLKuaiLe-Regular",
        "ZCOOLXiaoWei-Regular"
    ]

    /// 用实际字形覆盖情况筛选，避免仅凭英文字体名漏掉支持汉字的字体。
    public static func supportsChinese(_ postScriptName: String) -> Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 14, nil)
        let characters = Array("字体跑步".utf16)
        let count = characters.count
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        return characters.withUnsafeBufferPointer { characters in
            glyphs.withUnsafeMutableBufferPointer { glyphs in
                guard let characters = characters.baseAddress,
                      let glyphs = glyphs.baseAddress else { return false }
                return CTFontGetGlyphsForCharacters(
                    font, characters, glyphs, count
                )
            }
        }
    }

    /// 中文字体置顶，内置字体优先；去重后保留其他字体的本地化排序。
    public static func orderedFontNames(_ names: [String]) -> [String] {
        let unique = Array(Set(names)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        let chinese = unique.filter {
            featuredChineseFonts.contains($0) || supportsChinese($0)
        }
        let featured = featuredChineseFonts.filter(chinese.contains)
        return featured +
            chinese.filter { !featured.contains($0) } +
            unique.filter { !chinese.contains($0) }
    }

    public static func displayName(for postScriptName: String) -> String {
        let knownNames: [(String, String)] = [
            ("ZhiMangXing", "钟齐志莽行书"),
            ("MaShanZheng", "马善政毛笔字"),
            ("ZCOOLKuaiLe", "站酷快乐体"),
            ("ZCOOLXiaoWei", "站酷小薇体"),
            ("PingFang", "苹方"),
            ("Hannotate", "手札体"),
            ("HanziPen", "翩翩手写体"),
            ("Wawati", "娃娃体"),
            ("Lantinghei", "兰亭黑"),
            ("STSong", "华文宋体"),
            ("STKaiti", "华文楷体"),
            ("Kaiti", "楷体"),
            ("Songti", "宋体"),
            ("Heiti", "黑体"),
            ("HiraginoSansGB", "冬青黑体"),
            ("NotoSansCJK", "思源黑体"),
            ("NotoSerifCJK", "思源宋体"),
            ("NotoSansSC", "思源黑体"),
            ("NotoSerifSC", "思源宋体")
        ]
        if let known = knownNames.first(where: {
            postScriptName.lowercased().hasPrefix($0.0.lowercased())
        }) {
            return known.1
        }
        let font = CTFontCreateWithName(postScriptName as CFString, 14, nil)
        let family = CTFontCopyFamilyName(font) as String
        return "中文字体 · \(family)"
    }
}
