/// A GPS-seeded local-language suggestion. `endonym` is the language's own name
/// ("Français", never "French") — the banner surfaces it with a flag. Multiple
/// languages mean a multilingual country; `confidence` is downgraded near
/// borders or under degraded location accuracy.
public struct LanguageSuggestion: Sendable, Equatable, Codable {
    public var countryCode: String
    public var languages: [String]
    public var endonym: String
    public var confidence: Double

    public init(countryCode: String, languages: [String], endonym: String, confidence: Double) {
        self.countryCode = countryCode
        self.languages = languages
        self.endonym = endonym
        self.confidence = confidence
    }
}
