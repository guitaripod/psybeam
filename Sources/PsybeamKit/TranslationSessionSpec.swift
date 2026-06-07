/// The provider-agnostic request to open one turn-gated translation direction.
public struct TranslationSessionSpec: Sendable, Codable, Equatable {
    public var pair: LanguagePair
    public var direction: Side
    public var sessionId: String

    public init(pair: LanguagePair, direction: Side, sessionId: String) {
        self.pair = pair
        self.direction = direction
        self.sessionId = sessionId
    }
}

public extension TranslationSessionSpec {
    /// The BCP-47 tag the model should speak for this spec's active direction.
    var outputLanguage: String {
        pair.outputLanguage(for: direction)
    }
}
