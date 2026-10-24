import AppKit
import CoreText
import RunOverlayCore

/// 字体资源只注册和分类一次，避免封面编辑窗口重绘时重复扫描系统字体。
@MainActor
enum CoverEditorFontLibrary {
    static let fontNames: [String] = {
        var names = NSFontManager.shared.availableFonts
        for name in CoverFontCatalog.featuredChineseFonts {
            guard let url = Bundle.main.url(
                forResource: name,
                withExtension: "ttf",
                subdirectory: "Fonts"
            ) else { continue }
            var error: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(
                url as CFURL,
                .process,
                &error
            )
            if registered || NSFont(name: name, size: 16) != nil {
                names.append(name)
            }
        }
        return CoverFontCatalog.orderedFontNames(names)
    }()

    static let chineseFontNames: Set<String> = Set(
        fontNames.filter(CoverFontCatalog.supportsChinese)
    )

    static func displayName(for name: String) -> String {
        chineseFontNames.contains(name)
            ? CoverFontCatalog.displayName(for: name)
            : name
    }

    static func filteredNames(
        search: String,
        chineseOnly: Bool,
        including selectedName: String?
    ) -> [String] {
        var names = chineseOnly
            ? fontNames.filter(chineseFontNames.contains)
            : fontNames
        if let selectedName,
           !selectedName.isEmpty,
           !names.contains(selectedName),
           (!chineseOnly || CoverFontCatalog.supportsChinese(selectedName)) {
            names.insert(selectedName, at: 0)
        }
        guard !search.isEmpty else { return names }
        return names.filter {
            $0.localizedStandardContains(search) ||
                displayName(for: $0).localizedStandardContains(search)
        }
    }
}

/// 缓存同一字体/配色/描边宽度的缩略图，滑动设置时不会重复绘制。
@MainActor
enum CoverEditorPalettePreview {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        return cache
    }()

    static func image(
        for preset: CoverTextColorPreset,
        layer: CoverTextLayer?
    ) -> NSImage? {
        let fontName = layer?.fontName ?? "HelveticaNeue-Bold"
        let bold = layer?.isBold ?? true
        let italic = layer?.isItalic ?? false
        let strokeWidth = preset.strokeWidth(
            afterApplyingTo: layer?.strokeWidth ?? 0
        )
        let key = "\(preset.id)|\(fontName)|\(bold)|\(italic)|\(strokeWidth)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let sample = CoverTextLayer(
            text: "示例",
            fontName: fontName,
            isBold: bold,
            isItalic: italic,
            fontHeight: 0.62,
            colorHex: preset.textHex,
            strokeHex: preset.strokeHex,
            strokeWidth: strokeWidth,
            shadowOpacity: 0
        )
        guard let cgImage = try? CoverComposer().renderTextOverlay(
            imageSize: CGSize(width: 128, height: 64),
            layer: sample
        ) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: 128, height: 64))
        cache.setObject(image, forKey: key)
        return image
    }
}
