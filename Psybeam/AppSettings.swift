import Foundation

/// Raw values align with `UIUserInterfaceStyle` (unspecified/light/dark) so a
/// stored mode maps straight onto a window override.
enum AppearanceMode: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2
}

enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    private enum Key {
        static let travelerLanguage = "psybeam.travelerLanguage"
        static let localLanguage = "psybeam.localLanguage"
        static let autoDetectLocation = "psybeam.autoDetectLocation"
        static let keepScreenBright = "psybeam.keepScreenBright"
        static let appearance = "psybeam.appearance"
    }

    static var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: defaults.integer(forKey: Key.appearance)) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    static var travelerLanguage: String {
        get { defaults.string(forKey: Key.travelerLanguage) ?? (Locale.current.language.languageCode?.identifier ?? "en") }
        set { defaults.set(newValue, forKey: Key.travelerLanguage) }
    }

    static var localLanguage: String {
        get { defaults.string(forKey: Key.localLanguage) ?? "es" }
        set { defaults.set(newValue, forKey: Key.localLanguage) }
    }

    static var autoDetectLocation: Bool {
        get { (defaults.object(forKey: Key.autoDetectLocation) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Key.autoDetectLocation) }
    }

    static var keepScreenBright: Bool {
        get { (defaults.object(forKey: Key.keepScreenBright) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Key.keepScreenBright) }
    }
}
