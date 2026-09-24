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

    /// The same pair facing the other way.
    var swapped: LanguagePair {
        LanguagePair(traveler: local, local: traveler)
    }

    /// Whether two tags name one language. Only the base subtag counts, so
    /// `zh-Hant` and `zh`, or `pt-BR` and `pt`, are the same language.
    static func sameLanguage(_ lhs: String, _ rhs: String) -> Bool {
        baseLanguage(lhs) == baseLanguage(rhs)
    }

    /// Their language when nothing usable is stored: Spanish, the most-visited
    /// destination language, unless Spanish is your own language, then English.
    static func defaultLocal(forTraveler traveler: String) -> String {
        sameLanguage(traveler, "es") ? "en" : "es"
    }

    /// The stored local language, unless it is missing or collides with yours.
    /// A pair that translates into the language you already speak plays your
    /// own words back to you, so it falls back to the default destination.
    static func local(stored: String?, traveler: String) -> String {
        guard let stored, !stored.isEmpty, !sameLanguage(stored, traveler) else {
            return defaultLocal(forTraveler: traveler)
        }
        return stored
    }

    /// The pair after a GPS suggestion, or nil when it should be ignored. A
    /// place that speaks your own language means you are at home, not abroad,
    /// so it never overwrites the destination you set up.
    func applyingDetectedLocal(_ code: String) -> LanguagePair? {
        guard !code.isEmpty, code != local, !Self.sameLanguage(code, traveler) else { return nil }
        return LanguagePair(traveler: traveler, local: code)
    }

    /// The pair after you choose the language they speak. Choosing your own
    /// language swaps the sides instead of producing a same-language pair.
    func choosingLocal(_ code: String) -> LanguagePair {
        Self.sameLanguage(code, traveler) ? swapped : LanguagePair(traveler: traveler, local: code)
    }

    /// The pair after you choose the language you speak. Choosing theirs swaps
    /// the sides instead of producing a same-language pair.
    func choosingTraveler(_ code: String) -> LanguagePair {
        Self.sameLanguage(code, local) ? swapped : LanguagePair(traveler: code, local: local)
    }

    private static func baseLanguage(_ tag: String) -> String {
        let base = tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? tag
        return base.lowercased()
    }
}
