#if DEBUG
import Foundation
import PsybeamKit

/// The language pair a demo shows and the phrase-table keys that fill it.
struct DemoPhrasebook: Equatable {
    let pair: LanguagePair
    let travelerKey: String
    let localKey: String

    /// Parses `"<traveler>:<local>"`, e.g. `"en:ja"` or `"ja:zh-Hant"`. Nil
    /// for an unsupported language or a same-language pair.
    init?(spec: String) {
        let sides = spec.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        guard sides.count == 2,
              let traveler = Self.supportedBase(sides[0]),
              let local = Self.supportedBase(sides[1]),
              traveler != local
        else { return nil }
        pair = LanguagePair(traveler: traveler, local: local)
        travelerKey = DemoPhrases.key(for: sides[0])
        localKey = DemoPhrases.key(for: sides[1])
    }

    /// With no pair given: you speak the UI language (English when Psybeam
    /// doesn't ship it) and they speak English, or French when you already do.
    init(uiLanguage: String) {
        let traveler = Self.supportedBase(uiLanguage) ?? "en"
        let local = traveler == "en" ? "fr" : "en"
        pair = LanguagePair(traveler: traveler, local: local)
        travelerKey = traveler == "en" ? "en" : DemoPhrases.key(for: uiLanguage)
        localKey = local
    }

    /// Who says line `index`: even lines are the traveler's, odd the local's.
    static func speaker(ofLine index: Int) -> Side {
        index.isMultiple(of: 2) ? .traveler : .local
    }

    /// Line `index` as its listener reads it: the traveler's words in the
    /// local language, the local's reply in the traveler's.
    func caption(line index: Int) -> String {
        DemoPhrases.line(index, in: key(for: Self.speaker(ofLine: index).other))
    }

    /// Line `index` as its speaker said it, for the upright source line.
    func source(line index: Int) -> String {
        DemoPhrases.line(index, in: key(for: Self.speaker(ofLine: index)))
    }

    func key(for side: Side) -> String {
        side == .traveler ? travelerKey : localKey
    }

    private static func supportedBase(_ tag: String) -> String? {
        SupportedLanguages.codes.first { LanguagePair.sameLanguage($0, tag) }
    }
}

/// A demo launch, read from the environment of a DEBUG build. Nil when
/// `PSYBEAM_DEMO` is unset, which is every normal launch.
struct DemoConfiguration {
    /// The real free-tier grant a new identity receives on mako. A demo
    /// launch shows this instead of the live balance, since a simulator can
    /// never pass the App Attest check mako's identity endpoint requires and
    /// so always reads back a stuck 0.
    static let freeMinutesGrant = 5

    let mode: String
    let phrasebook: DemoPhrasebook
    let coach: Bool
    let level: Float?
    let script: [DemoScriptEvent]

    init?(environment: [String: String], uiLanguage: String) {
        guard let mode = environment["PSYBEAM_DEMO"], !mode.isEmpty else { return nil }
        self.mode = mode
        phrasebook = environment["PSYBEAM_DEMO_PAIR"].flatMap(DemoPhrasebook.init(spec:))
            ?? DemoPhrasebook(uiLanguage: uiLanguage)
        coach = environment["PSYBEAM_DEMO_COACH"] == "1"
        level = environment["PSYBEAM_DEMO_LEVEL"].flatMap(Float.init)
        script = mode == "script" ? Self.loadScript(environment["PSYBEAM_DEMO_SCRIPT"]) : []
    }

    /// The first-run stage the demo opens on. Nothing a demo does is persisted.
    var initialStage: FirstRunStage {
        switch mode {
        case "destination": .chooseDestination
        case "coach": .holdYours
        case "coach-theirs": .holdTheirs
        default: coach ? .holdYours : .done
        }
    }

    /// `PSYBEAM_DEMO_SCRIPT` is inline JSON when it starts with `[`, otherwise
    /// a path to a JSON file (the simulator can read the host's files). A
    /// missing or unreadable script falls back to the built-in exchange.
    private static func loadScript(_ value: String?) -> [DemoScriptEvent] {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return DemoScriptEvent.defaultScript
        }
        let data = value.hasPrefix("[") ? Data(value.utf8) : FileManager.default.contents(atPath: value)
        do {
            guard let data else { throw CocoaError(.fileReadNoSuchFile) }
            return try JSONDecoder().decode([DemoScriptEvent].self, from: data)
        } catch {
            AppLogger.shared.error("demo script unreadable, playing the default: \(error)", category: .ui)
            return DemoScriptEvent.defaultScript
        }
    }
}

/// One timed step of a `PSYBEAM_DEMO=script` recording. `at` is seconds after
/// the conversation screen appears. Caption and source events without `text`
/// use the phrase table: `line` when given, else the speaker's next line.
struct DemoScriptEvent: Decodable, Equatable {
    enum Kind: String, Decodable {
        case hold, release, text, append, stream, source
        case streamSource = "stream_source"
        case state, pair
    }

    let at: Double
    let speaker: Side
    let event: Kind
    let text: String?
    let line: Int?
    let duration: Double?
    let state: String?
    let pair: String?

    init(
        at: Double, speaker: Side = .traveler, event: Kind, text: String? = nil, line: Int? = nil,
        duration: Double? = nil, state: String? = nil, pair: String? = nil
    ) {
        self.at = at
        self.speaker = speaker
        self.event = event
        self.text = text
        self.line = line
        self.duration = duration
        self.state = state
        self.pair = pair
    }

    private enum CodingKeys: String, CodingKey {
        case at, speaker, event, text, line, duration, state, pair
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = try container.decode(Double.self, forKey: .at)
        speaker = try container.decodeIfPresent(Side.self, forKey: .speaker) ?? .traveler
        event = try container.decode(Kind.self, forKey: .event)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        pair = try container.decodeIfPresent(String.self, forKey: .pair)
    }

    /// Two full exchanges, about 20 seconds: the length of an App Preview.
    static let defaultScript: [DemoScriptEvent] = [
        DemoScriptEvent(at: 0.8, speaker: .traveler, event: .hold),
        DemoScriptEvent(at: 1.2, speaker: .traveler, event: .streamSource, duration: 1.6),
        DemoScriptEvent(at: 1.5, speaker: .traveler, event: .stream, duration: 2.0),
        DemoScriptEvent(at: 3.9, speaker: .traveler, event: .release),
        DemoScriptEvent(at: 6.2, speaker: .local, event: .hold),
        DemoScriptEvent(at: 6.6, speaker: .local, event: .streamSource, duration: 1.4),
        DemoScriptEvent(at: 6.9, speaker: .local, event: .stream, duration: 1.8),
        DemoScriptEvent(at: 9.0, speaker: .local, event: .release),
        DemoScriptEvent(at: 11.2, speaker: .traveler, event: .hold),
        DemoScriptEvent(at: 11.6, speaker: .traveler, event: .streamSource, duration: 1.2),
        DemoScriptEvent(at: 11.9, speaker: .traveler, event: .stream, duration: 1.5),
        DemoScriptEvent(at: 13.8, speaker: .traveler, event: .release),
        DemoScriptEvent(at: 16.0, speaker: .local, event: .hold),
        DemoScriptEvent(at: 16.4, speaker: .local, event: .streamSource, duration: 1.3),
        DemoScriptEvent(at: 16.7, speaker: .local, event: .stream, duration: 1.6),
        DemoScriptEvent(at: 18.7, speaker: .local, event: .release),
    ]
}
#endif
