import Foundation

public struct ReleaseNote: Identifiable, Equatable, Sendable {
    public let build: Int
    public let date: String
    public let titleKey: String
    public let changeKeys: [String]

    public var id: Int { build }

    public init(
        build: Int,
        date: String,
        titleKey: String,
        changeKeys: [String]
    ) {
        self.build = build
        self.date = date
        self.titleKey = titleKey
        self.changeKeys = changeKeys
    }

    public func version(base: String) -> String {
        String(format: "%@-%03d", base, build)
    }
}

/// 只记录可核对的安装包版本；新版本打包时同步更新此列表。
public enum ReleaseHistory {
    public static let published: [ReleaseNote] = [
        ReleaseNote(
            build: 20,
            date: "2026-10-11",
            titleKey: "ui.release.020.title",
            changeKeys: ["ui.release.020.elevationProfile"]
        ),
        ReleaseNote(
            build: 19,
            date: "2026-10-07",
            titleKey: "ui.release.019.title",
            changeKeys: [
                "ui.release.019.matchDiagnostics",
                "ui.release.019.exportValidation"
            ]
        ),
        ReleaseNote(
            build: 18,
            date: "2026-10-07",
            titleKey: "ui.release.018.title",
            changeKeys: [
                "ui.release.018.duplicateText",
                "ui.release.018.clearActivity"
            ]
        ),
        ReleaseNote(
            build: 17,
            date: "2026-10-07",
            titleKey: "ui.release.017.title",
            changeKeys: [
                "ui.release.017.palette",
                "ui.release.017.fontTraits",
                "ui.release.017.cjkFonts",
                "ui.release.017.italicFrame",
                "ui.release.017.fontFilter",
                "ui.release.017.palettePreview"
            ]
        ),
        ReleaseNote(
            build: 16,
            date: "2026-10-05",
            titleKey: "ui.release.016.title",
            changeKeys: ["ui.release.016.rebuild"]
        ),
        ReleaseNote(
            build: 15,
            date: "2026-10-05",
            titleKey: "ui.release.015.title",
            changeKeys: [
                "ui.release.015.frame",
                "ui.release.015.font",
                "ui.release.015.accent",
                "ui.release.015.history"
            ]
        ),
        ReleaseNote(
            build: 14,
            date: "2026-10-05",
            titleKey: "ui.release.014.title",
            changeKeys: [
                "ui.release.014.rotation",
                "ui.release.014.buttons",
                "ui.release.014.tabs"
            ]
        ),
        ReleaseNote(
            build: 13,
            date: "2026-10-05",
            titleKey: "ui.release.013.title",
            changeKeys: [
                "ui.release.013.editor",
                "ui.release.013.occlusion",
                "ui.release.013.performance"
            ]
        ),
        ReleaseNote(
            build: 12,
            date: "2026-10-03",
            titleKey: "ui.release.012.title",
            changeKeys: [
                "ui.release.012.snapshot",
                "ui.release.012.overlay"
            ]
        )
    ]

    public static func note(forVersion version: String, base: String) -> ReleaseNote? {
        published.first { $0.version(base: base) == version }
    }

    /// 已完成但尚未打包的新功能单独显示，不混入旧安装包版本。
    public static let developmentChangeKeys: [String] = [
        "ui.release.dev.coverCenterSnap",
        "ui.release.dev.exportUnlock",
        "ui.release.dev.backgroundExport",
        "ui.release.dev.exportDirectoryPermission",
        "ui.release.dev.coverDeselection",
        "ui.release.dev.calligraphyFont",
        "ui.release.dev.smartEditLocal",
        "ui.release.dev.smartEditSourceLanguage",
        "ui.release.dev.smartEditSplitPoints"
    ]
}
