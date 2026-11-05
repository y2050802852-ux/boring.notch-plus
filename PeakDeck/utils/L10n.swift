//
//  L10n.swift
//  PeakDeck
//
//  In-app language selection + locale plumbing.
//

import SwiftUI
import Defaults

/// Interface language of the app. `system` keeps the standard behavior of
/// resolving the localization catalog from the macOS system language.
enum AppLanguage: String, CaseIterable, Identifiable, Defaults.Serializable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// nil means "follow the system"; otherwise the bundle lproj name.
    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        }
    }
}

enum L10n {
    /// The locale every SwiftUI tree should resolve localized strings with.
    @MainActor
    static var locale: Locale {
        guard let identifier = Defaults[.appLanguage].localeIdentifier else {
            return .current
        }
        return Locale(identifier: identifier)
    }

    /// Resolve a catalog key for the selected language from contexts the
    /// SwiftUI locale environment cannot reach (AppKit dialogs, managers,
    /// notification content). Keys fall back to their English source value.
    static func string(_ key: String) -> String {
        guard let identifier = Defaults[.appLanguage].localeIdentifier else {
            return Bundle.main.localizedString(forKey: key, value: key, table: nil)
        }
        guard let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// Resolves a format key (e.g. "Manual city: %@") and substitutes args.
    static func string(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), arguments: args)
    }

    /// Pin the app's localization preference so AppKit-rendered UI that the
    /// locale environment cannot reach (menus, third-party package views)
    /// follows the selection; applies to newly launched processes.
    static func applyLanguageOverride() {
        let identifier = Defaults[.appLanguage].localeIdentifier
        if let identifier {
            UserDefaults.standard.set([identifier], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
}

/// Wraps every root SwiftUI tree so localized Texts resolve against the
/// app language preference instead of only the macOS system language.
/// Observing the preference makes the switch apply live.
struct LocalizedRootView<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Default(.appLanguage) private var appLanguage

    var body: some View {
        content()
            .environment(\.locale, appLanguage.localeIdentifier.map(Locale.init(identifier:)) ?? .current)
    }
}
