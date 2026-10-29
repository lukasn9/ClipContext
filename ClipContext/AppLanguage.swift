import Foundation
import ObjectiveC
import SwiftUI

/// Resolves strings from the in-app language choice instead of the language the process launched with.
nonisolated private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let override = objc_getAssociatedObject(self, &AppLanguage.overrideKey) as? Bundle {
            return override.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

nonisolated enum AppLanguage {
    nonisolated(unsafe) fileprivate static var overrideKey: UInt8 = 0

    /// Concrete language code ("fr", "pt-BR", …) for a setting that may be "system".
    static func resolvedCode(for setting: String) -> String {
        if setting != "system" { return setting }
        let preferences = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
            ?? Locale.preferredLanguages
        let available = Bundle.main.localizations.filter { $0 != "Base" }
        return Bundle.preferredLocalizations(from: available, forPreferences: preferences).first ?? "en"
    }

    /// Switches NSLocalizedString / Bundle lookups to the chosen language immediately.
    static func apply(_ setting: String) {
        object_setClass(Bundle.main, LocalizedBundle.self)
        let code = resolvedCode(for: setting)
        let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
        objc_setAssociatedObject(Bundle.main, &overrideKey, bundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

/// Looks up a string in the active in-app language. `String(localized:)` bypasses the bundle override, so use this.
nonisolated func loc(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

/// Re-renders its content with the new language and locale whenever the language setting changes.
struct LocalizedRoot<Content: View>: View {
    @ObservedObject private var settings = SettingsStore.shared
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.locale, settings.locale)
            .id(settings.languageCode)
    }
}
