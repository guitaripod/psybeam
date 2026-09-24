/// The languages Psybeam offers in its pickers, as bare base-language tags.
public enum SupportedLanguages {
    /// The language menus' order.
    public static let codes = [
        "en", "es", "fr", "de", "it", "pt", "nl", "ru", "pl", "tr", "el",
        "ar", "he", "hi", "ja", "ko", "zh", "th", "vi", "id", "fi", "sv",
    ]

    /// Every supported language, most-travelled-to first, so the destination
    /// a new user is most likely heading to sits at the top of the picker.
    /// English leads: English-speaking countries together draw the most
    /// visitors, and an English speaker never sees it, since the picker
    /// leaves out the traveler's own language.
    public static let byTravelPopularity = [
        "en", "es", "fr", "it", "ja", "de", "pt", "ko", "th", "zh", "el",
        "tr", "vi", "id", "nl", "ar", "hi", "he", "pl", "sv", "fi", "ru",
    ]

    /// The destinations to offer someone who speaks `traveler`: every
    /// supported language except their own, most-travelled-to first.
    public static func destinations(forTraveler traveler: String) -> [String] {
        byTravelPopularity.filter { !LanguagePair.sameLanguage($0, traveler) }
    }
}
