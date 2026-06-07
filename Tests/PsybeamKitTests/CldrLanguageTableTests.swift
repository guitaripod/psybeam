import Testing
@testable import PsybeamKit

@Suite("CldrLanguageTable")
struct CldrLanguageTableTests {
    let table = CldrLanguageTable()

    @Test("Multilingual Switzerland resolves de, fr, it in order")
    func switzerland() {
        #expect(table.languages(forCountry: "CH") == ["de", "fr", "it"])
    }

    @Test("Multilingual Belgium resolves nl, fr")
    func belgium() {
        #expect(table.languages(forCountry: "BE") == ["nl", "fr"])
    }

    @Test("Canada resolves en, fr")
    func canada() {
        #expect(table.languages(forCountry: "CA") == ["en", "fr"])
    }

    @Test("Spain resolves es, ca")
    func spain() {
        #expect(table.languages(forCountry: "ES") == ["es", "ca"])
    }

    @Test("India resolves hi, en")
    func india() {
        #expect(table.languages(forCountry: "IN") == ["hi", "en"])
    }

    @Test("Lookup is case-insensitive on the country code")
    func caseInsensitive() {
        #expect(table.languages(forCountry: "ch") == table.languages(forCountry: "CH"))
        #expect(table.languages(forCountry: "fr") == ["fr"])
    }

    @Test("Unknown country resolves empty")
    func unknown() {
        #expect(table.languages(forCountry: "ZZ").isEmpty)
    }

    @Test("Endonyms surface the language's own name")
    func endonyms() {
        #expect(table.endonym(forLanguage: "fr") == "Français")
        #expect(table.endonym(forLanguage: "DE") == "Deutsch")
        #expect(table.endonym(forLanguage: "zz") == nil)
    }

    @Test("Every seeded country maps to 1-3 languages")
    func arityBounds() {
        for (country, langs) in CldrLanguageTable.seed {
            #expect((1...3).contains(langs.count), "\(country) has \(langs.count) languages")
        }
    }

    @Test("A custom table overrides the seed")
    func customTable() {
        let custom = CldrLanguageTable(table: ["XX": ["qq"]])
        #expect(custom.languages(forCountry: "XX") == ["qq"])
        #expect(custom.languages(forCountry: "CH").isEmpty)
    }
}
