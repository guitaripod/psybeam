import Foundation

/// How Psybeam writes a language's name. The talk buttons and language menus
/// use the language's own name so each person can find theirs; running text
/// uses the name in the app's UI language.
enum LanguageNames {
    /// The language's name for itself, as the buttons show it (`"ja"` → `"日本語"`).
    static func endonym(_ code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }

    /// The language's name in the UI language, as it reads mid-sentence
    /// (`"ja"` → `"japonais"` in French, `"Japanese"` in English).
    static func inUILanguage(_ code: String) -> String {
        uiLocale.localizedString(forLanguageCode: code) ?? endonym(code)
    }

    /// The UI-language name set as a standalone list item: only the first
    /// letter is raised, following the UI locale's casing rules.
    static func listTitle(_ code: String) -> String {
        let name = inUILanguage(code)
        guard let first = name.first else { return name }
        return String(first).uppercased(with: uiLocale) + name.dropFirst()
    }

    /// The locale the app's strings are actually shown in, which can differ
    /// from the device locale when the UI language isn't one Psybeam ships.
    private static var uiLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
