/// A curated, network-free country → language table seeded from CLDR
/// `territoryInfo`, ranked by official status then population, with
/// English-as-L2 suppressed where it is not the street language. The ranking is
/// editorial, not derivable — it is hand-curated and test-fixtured. Plain static
/// data, Linux-safe, no `Locale` reads (the device passes its locale in
/// explicitly). 1–3 languages per ISO 3166-1 alpha-2 code.
public struct CldrLanguageTable: Sendable {
    private let table: [String: [String]]
    private let endonyms: [String: String]

    public init() {
        self.table = Self.seed
        self.endonyms = Self.endonymSeed
    }

    public init(table: [String: [String]], endonyms: [String: String] = [:]) {
        self.table = table
        self.endonyms = endonyms
    }

    /// The ranked languages for an ISO 3166-1 alpha-2 country code
    /// (case-insensitive). Empty when the country is not in the seed.
    public func languages(forCountry iso2: String) -> [String] {
        table[iso2.uppercased()] ?? []
    }

    /// The language's own name, when known (e.g. `"fr"` → `"Français"`).
    public func endonym(forLanguage code: String) -> String? {
        endonyms[code.lowercased()]
    }
}

public extension CldrLanguageTable {
    static let seed: [String: [String]] = [
        "US": ["en"],
        "GB": ["en"],
        "IE": ["en", "ga"],
        "FR": ["fr"],
        "DE": ["de"],
        "AT": ["de"],
        "IT": ["it"],
        "ES": ["es", "ca"],
        "PT": ["pt"],
        "NL": ["nl"],
        "BE": ["nl", "fr"],
        "CH": ["de", "fr", "it"],
        "LU": ["lb", "fr", "de"],
        "SE": ["sv"],
        "NO": ["nb"],
        "DK": ["da"],
        "FI": ["fi", "sv"],
        "PL": ["pl"],
        "CZ": ["cs"],
        "GR": ["el"],
        "TR": ["tr"],
        "RU": ["ru"],
        "UA": ["uk"],
        "JP": ["ja"],
        "KR": ["ko"],
        "CN": ["zh"],
        "TW": ["zh"],
        "HK": ["zh", "en"],
        "TH": ["th"],
        "VN": ["vi"],
        "ID": ["id"],
        "MY": ["ms", "en"],
        "PH": ["fil", "en"],
        "IN": ["hi", "en"],
        "SA": ["ar"],
        "AE": ["ar", "en"],
        "EG": ["ar"],
        "IL": ["he"],
        "MX": ["es"],
        "BR": ["pt"],
        "AR": ["es"],
        "CA": ["en", "fr"],
        "AU": ["en"],
        "NZ": ["en"],
        "MC": ["fr"],
        "AD": ["ca", "es"],
        "SM": ["it"],
        "VA": ["it"],
        "LI": ["de"],
        "MT": ["mt", "en"],
        "CY": ["el"],
        "IS": ["is"],
        "EE": ["et"],
        "LV": ["lv"],
        "LT": ["lt"],
        "SK": ["sk"],
        "SI": ["sl"],
        "HR": ["hr"],
        "RS": ["sr"],
        "BG": ["bg"],
        "RO": ["ro"],
        "HU": ["hu"],
        "AL": ["sq"],
        "MK": ["mk"],
        "GE": ["ka"],
        "MA": ["ar", "fr"],
        "TN": ["ar", "fr"],
        "DZ": ["ar", "fr"],
        "JO": ["ar"],
        "LB": ["ar", "fr"],
        "QA": ["ar"],
        "KW": ["ar"],
        "CL": ["es"],
        "CO": ["es"],
        "PE": ["es"],
        "VE": ["es"],
        "CR": ["es"],
        "GT": ["es"],
        "DO": ["es"]
    ]

    static let endonymSeed: [String: String] = [
        "en": "English",
        "ga": "Gaeilge",
        "fr": "Français",
        "de": "Deutsch",
        "it": "Italiano",
        "es": "Español",
        "ca": "Català",
        "pt": "Português",
        "nl": "Nederlands",
        "lb": "Lëtzebuergesch",
        "sv": "Svenska",
        "nb": "Norsk",
        "da": "Dansk",
        "fi": "Suomi",
        "pl": "Polski",
        "cs": "Čeština",
        "el": "Ελληνικά",
        "tr": "Türkçe",
        "ru": "Русский",
        "uk": "Українська",
        "ja": "日本語",
        "ko": "한국어",
        "zh": "中文",
        "th": "ไทย",
        "vi": "Tiếng Việt",
        "id": "Bahasa Indonesia",
        "ms": "Bahasa Melayu",
        "fil": "Filipino",
        "hi": "हिन्दी",
        "ar": "العربية",
        "he": "עברית"
    ]
}
