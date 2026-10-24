import Foundation
import RunOverlayCore

enum AppStrings {
    static func text(_ key: String, fallback: String? = nil) -> String {
        RunOverlayLocalization.appText(key, fallback: fallback)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        RunOverlayLocalization.appFormat(
            key,
            arguments: arguments
        )
    }
}
