/// A directed pairing of BCP-47 language tags: the traveler's language and the
/// local language seeded by GPS. The realtime model auto-detects the spoken
/// source; this pair only seeds the output target per direction.
public struct LanguagePair: Sendable, Codable, Equatable {
    public var traveler: String
    public var local: String

    public init(traveler: String, local: String) {
        self.traveler = traveler
        self.local = local
    }
}

public extension LanguagePair {
    /// The BCP-47 tag the model should *speak* for the given active direction.
    func outputLanguage(for direction: Side) -> String {
        switch direction {
        case .traveler: local
        case .local: traveler
        }
    }
}
