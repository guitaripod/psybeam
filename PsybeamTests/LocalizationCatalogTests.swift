import Foundation
import Testing

@Suite("Localization catalog")
struct LocalizationCatalogTests {
    private let languages = ["de", "fr", "es", "it", "ja", "ko", "zh-Hans", "zh-Hant", "pt-BR"]
    private let infoPlistKeys = [
        "NSMicrophoneUsageDescription",
        "NSLocationWhenInUseUsageDescription",
        "NSCameraUsageDescription",
    ]
    private let specifierPattern = try! NSRegularExpression(
        pattern: #"%(?:(\d+)\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfeEgGcCsSpaAF%])"#)

    @Test("Every supported language ships a compiled Localizable.strings")
    func everyLanguageShipsStrings() {
        for language in languages {
            #expect(table("Localizable", language) != nil, "\(language).lproj/Localizable.strings is not in the app")
        }
    }

    @Test("Every language covers the same keys, with no blank translation")
    func coverageIsComplete() throws {
        let reference = try #require(table("Localizable", "de"))
        for language in languages {
            let translations = try #require(table("Localizable", language))
            #expect(
                Set(translations.keys) == Set(reference.keys),
                "\(language) is missing \(Set(reference.keys).subtracting(translations.keys))"
            )
            for (key, value) in translations where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Issue.record("\(language) has a blank translation for \(key)")
            }
        }
    }

    /// The keys of this catalog *are* the English source strings, so a translation's format
    /// specifiers can be compared straight against its key. A mismatch crashes at runtime in a
    /// language the author cannot read, which is why it is asserted rather than reviewed.
    @Test("Format specifiers survive translation")
    func formatSpecifiersMatchSource() throws {
        for language in languages {
            let translations = try #require(table("Localizable", language))
            for (key, value) in translations {
                #expect(
                    specifiers(in: value) == specifiers(in: key),
                    "\(language) specifier mismatch for \"\(key)\" → \"\(value)\""
                )
            }
        }
    }

    @Test("Permission prompts are translated in every language")
    func infoPlistPromptsAreTranslated() throws {
        for language in languages {
            let translations = try #require(table("InfoPlist", language))
            for key in infoPlistKeys {
                #expect(translations[key]?.isEmpty == false, "\(language) is missing \(key)")
            }
        }
    }

    private func table(_ name: String, _ language: String) -> [String: String]? {
        guard let url = Bundle.main.url(
            forResource: name, withExtension: "strings", subdirectory: "\(language).lproj"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return plist as? [String: String]
    }

    /// Maps each argument position to its length modifier and conversion, so `%@ (%@)` and
    /// `%1$@ (%2$@)` compare equal while a dropped, added or retyped argument does not.
    private func specifiers(in string: String) -> [Int: String] {
        var result: [Int: String] = [:]
        var implicitIndex = 0
        let range = NSRange(string.startIndex..., in: string)
        for match in specifierPattern.matches(in: string, range: range) {
            let conversion = capture(match, 3, in: string) ?? ""
            guard conversion != "%" else { continue }
            implicitIndex += 1
            let position = capture(match, 1, in: string).flatMap(Int.init) ?? implicitIndex
            result[position] = (capture(match, 2, in: string) ?? "") + conversion
        }
        return result
    }

    private func capture(_ match: NSTextCheckingResult, _ index: Int, in string: String) -> String? {
        guard let range = Range(match.range(at: index), in: string) else { return nil }
        return String(string[range])
    }
}
