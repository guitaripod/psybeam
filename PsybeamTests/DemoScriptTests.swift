#if DEBUG
import Foundation
import PsybeamKit
import Testing
@testable import Psybeam

@MainActor
@Suite("Demo phrases and scripts")
struct DemoScriptTests {
    @Test("Every supported language has the full scripted exchange")
    func phraseTableCoversEveryLanguage() {
        let keys = SupportedLanguages.codes.map { $0 == "zh" ? "zh-Hans" : $0 } + ["zh-Hant"]
        for key in keys {
            let lines = DemoPhrases.lines[key] ?? []
            #expect(lines.count == 4, "\(key) has \(lines.count) lines")
            for line in lines {
                #expect(!line.trimmingCharacters(in: .whitespaces).isEmpty, "\(key) has a blank line")
            }
        }
        #expect(Set(DemoPhrases.lines.keys) == Set(keys))
    }

    @Test("A demo pair parses, keeps Chinese script and rejects nonsense")
    func pairParsing() throws {
        let japanese = try #require(DemoPhrasebook(spec: "en:ja"))
        #expect(japanese.pair == LanguagePair(traveler: "en", local: "ja"))
        let taiwan = try #require(DemoPhrasebook(spec: "en:zh-Hant"))
        #expect(taiwan.pair == LanguagePair(traveler: "en", local: "zh"))
        #expect(taiwan.localKey == "zh-Hant")
        #expect(DemoPhrasebook(spec: "en:en") == nil)
        #expect(DemoPhrasebook(spec: "en:xx") == nil)
        #expect(DemoPhrasebook(spec: "en") == nil)
    }

    @Test("Without a pair the demo speaks the UI language to an English speaker")
    func defaultPair() {
        #expect(DemoPhrasebook(uiLanguage: "ja").pair == LanguagePair(traveler: "ja", local: "en"))
        #expect(DemoPhrasebook(uiLanguage: "en").pair == LanguagePair(traveler: "en", local: "fr"))
        #expect(DemoPhrasebook(uiLanguage: "zh-Hant").travelerKey == "zh-Hant")
        #expect(DemoPhrasebook(uiLanguage: "da").pair == LanguagePair(traveler: "en", local: "fr"))
    }

    @Test("Captions face the listener and sources stay in the speaker's language")
    func captionLanguages() throws {
        let book = try #require(DemoPhrasebook(spec: "en:ja"))
        #expect(book.caption(line: 0) == DemoPhrases.line(0, in: "ja"))
        #expect(book.source(line: 0) == DemoPhrases.line(0, in: "en"))
        #expect(book.caption(line: 1) == DemoPhrases.line(1, in: "en"))
        #expect(book.source(line: 1) == DemoPhrases.line(1, in: "ja"))
    }

    @Test("A script decodes from the documented JSON shape")
    func decodesScript() throws {
        let json = #"""
        [{"at":0.5,"speaker":"traveler","event":"hold"},
         {"at":1.0,"speaker":"traveler","event":"text","text":"Hola"},
         {"at":3.0,"speaker":"traveler","event":"release"},
         {"at":4.0,"speaker":"local","event":"stream_source","duration":1.5},
         {"at":5.0,"event":"pair","pair":"en:ko"}]
        """#
        let events = try JSONDecoder().decode([DemoScriptEvent].self, from: Data(json.utf8))
        #expect(events.count == 5)
        #expect(events[1] == DemoScriptEvent(at: 1.0, speaker: .traveler, event: .text, text: "Hola"))
        #expect(events[3].event == .streamSource)
        #expect(events[4].speaker == .traveler)
    }

    @Test("Streaming a line yields its words in order and rebuilds it exactly")
    func streamingRebuildsText() {
        for key in DemoPhrases.lines.keys {
            let line = DemoPhrases.line(0, in: key)
            let chunks = DemoScriptPlayer.streamChunks(line, language: key)
            #expect(chunks.count > 2, "\(key) streams in \(chunks.count) chunks")
            #expect(chunks.joined() == line, "\(key) rebuilt as \(chunks.joined())")
        }
    }

    @Test("Holds advance each speaker through the exchange, in time order")
    func expansionUsesNextLines() throws {
        let book = try #require(DemoPhrasebook(spec: "en:es"))
        let events = [
            DemoScriptEvent(at: 2.0, speaker: .local, event: .hold),
            DemoScriptEvent(at: 0.0, speaker: .traveler, event: .hold),
            DemoScriptEvent(at: 0.5, speaker: .traveler, event: .text),
            DemoScriptEvent(at: 2.5, speaker: .local, event: .text),
            DemoScriptEvent(at: 4.0, speaker: .traveler, event: .hold),
            DemoScriptEvent(at: 4.5, speaker: .traveler, event: .source),
        ]
        let steps = DemoScriptPlayer.expand(events, phrasebook: book)
        #expect(steps.map(\.at) == steps.map(\.at).sorted())
        #expect(steps.contains(DemoStep(at: 0.5, action: .caption(.traveler, DemoPhrases.line(0, in: "es")))))
        #expect(steps.contains(DemoStep(at: 2.5, action: .caption(.local, DemoPhrases.line(1, in: "en")))))
        #expect(steps.contains(DemoStep(at: 4.5, action: .source(.traveler, DemoPhrases.line(2, in: "en")))))
    }

    @Test("A stream spreads its chunks across the requested duration")
    func streamTiming() throws {
        let book = try #require(DemoPhrasebook(spec: "en:fr"))
        let steps = DemoScriptPlayer.expand(
            [DemoScriptEvent(at: 1.0, speaker: .traveler, event: .stream, text: "one two three", duration: 1.0)],
            phrasebook: book)
        #expect(steps == [
            DemoStep(at: 1.0, action: .append(.traveler, "one ")),
            DemoStep(at: 1.5, action: .append(.traveler, "two ")),
            DemoStep(at: 2.0, action: .append(.traveler, "three")),
        ])
    }
}
#endif
