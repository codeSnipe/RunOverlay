import Foundation

public enum RunOverlayLanguage: String, CaseIterable, Codable, Hashable, Sendable {
    case system
    case chineseSimplified = "zh-Hans"
    case english = "en"
    case japanese = "ja"

    public var displayName: String {
        switch self {
        case .system:
            RunOverlayLocalization.text("language.system", in: .main)
        case .chineseSimplified:
            RunOverlayLocalization.text("language.chineseSimplified", in: .main)
        case .english:
            RunOverlayLocalization.text("language.english", in: .main)
        case .japanese:
            RunOverlayLocalization.text("language.japanese", in: .main)
        }
    }
}

public enum RunOverlayLocalization {
    private static let languagePreferenceKey = "runoverlay.appLanguage"
    private static let videoTextStrings: [VideoTextLanguage: [String: String]] = {
        let bundle = Bundle.module
        return Dictionary(uniqueKeysWithValues: VideoTextLanguage.allCases.map { language in
            let folder = language.rawValue
            guard let path = bundle.path(forResource: folder, ofType: "lproj")
                ?? bundle.path(forResource: folder.lowercased(), ofType: "lproj"),
                let localizedBundle = Bundle(path: path),
                let stringsPath = localizedBundle.path(
                    forResource: "Localizable",
                    ofType: "strings"
                ),
                let strings = NSDictionary(contentsOfFile: stringsPath) as? [String: String]
            else {
                return (language, [:])
            }
            return (language, strings)
        })
    }()

    public static var language: RunOverlayLanguage {
        get {
            guard let rawValue = UserDefaults.standard.string(
                forKey: languagePreferenceKey
            ) else {
                return .system
            }
            return RunOverlayLanguage(rawValue: rawValue) ?? .system
        }
        set {
            UserDefaults.standard.set(
                newValue.rawValue,
                forKey: languagePreferenceKey
            )
        }
    }

    public static var locale: Locale {
        language == .system ? .current : Locale(identifier: language.rawValue)
    }

    public static func text(_ key: String, in bundle: Bundle? = nil) -> String {
        let lookupBundle = bundle ?? .module
        return NSLocalizedString(
            key,
            bundle: localizedBundle(from: lookupBundle),
            comment: ""
        )
    }

    public static func text(_ key: String, videoLanguage: VideoTextLanguage) -> String {
        videoTextStrings[videoLanguage]?[key] ?? key
    }

    public static func format(
        _ key: String,
        in bundle: Bundle? = nil,
        arguments: [CVarArg]
    ) -> String {
        String(
            format: text(key, in: bundle),
            locale: locale,
            arguments: arguments
        )
    }

    private static func localizedBundle(from bundle: Bundle) -> Bundle {
        guard language != .system else {
            return bundle
        }
        let localization = language.rawValue.lowercased()
        let path = bundle.path(
            forResource: localization,
            ofType: "lproj"
        ) ?? bundle.path(
            forResource: language.rawValue,
            ofType: "lproj"
        )
        guard let path,
              let localizedBundle = Bundle(path: path) else {
            return bundle
        }
        return localizedBundle
    }

    public static func appText(_ key: String, fallback: String? = nil) -> String {
        NSLocalizedString(
            key,
            bundle: localizedBundle(from: .main),
            value: fallback ?? key,
            comment: ""
        )
    }

    public static func appFormat(
        _ key: String,
        arguments: [CVarArg]
    ) -> String {
        String(
            format: appText(key),
            locale: locale,
            arguments: arguments
        )
    }
}
