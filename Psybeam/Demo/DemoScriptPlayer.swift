#if DEBUG
import Foundation
import PsybeamKit

/// The conversation screen's production render paths, exposed so a scripted
/// recording drives exactly what a real session would: the talk buttons'
/// active state, the leg states, the streamed captions and the turn ending.
@MainActor
protocol DemoStage: AnyObject {
    func demoHold(_ speaker: Side)
    func demoRelease(_ speaker: Side)
    func demoCaption(_ text: String, speaker: Side)
    func demoSource(_ text: String)
    func demoState(_ state: TranslationState, speaker: Side)
    func demoPair(_ pair: LanguagePair)
    func demoLevel(_ level: Float)
    func demoTurnFinished(_ speaker: Side)
}

/// A concrete, time-stamped step, with every phrase-table lookup and caption
/// stream already resolved.
enum DemoAction: Equatable {
    case hold(Side)
    case release(Side)
    case caption(Side, String)
    case append(Side, String)
    case source(Side, String)
    case appendSource(Side, String)
    case state(Side, TranslationState)
    case pair(DemoPhrasebook)
}

struct DemoStep: Equatable {
    let at: Double
    let action: DemoAction
}

/// Plays a `PSYBEAM_DEMO=script` timeline in real time. It stands in for the
/// two translation legs, and only for them: holds reset the speaker's caption,
/// captions stream in as appended deltas, and a turn ends on the same 1.2 s
/// caption quiescence after release that `TranslationLeg` uses.
@MainActor
final class DemoScriptPlayer {
    private weak var stage: (any DemoStage)?
    private let steps: [DemoStep]
    private var holding: Side?
    private var captions: [Side: String] = [:]
    private var sources: [Side: String] = [:]
    private var finished: Set<Side> = []
    private var settleTasks: [Side: Task<Void, Never>] = [:]
    private var levelTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?

    init(events: [DemoScriptEvent], phrasebook: DemoPhrasebook, stage: any DemoStage) {
        self.steps = Self.expand(events, phrasebook: phrasebook)
        self.stage = stage
    }

    func start() {
        guard runTask == nil else { return }
        let steps = steps
        runTask = Task { [weak self] in
            let clock = ContinuousClock()
            let origin = clock.now
            for step in steps {
                try? await clock.sleep(until: origin.advanced(by: .milliseconds(Int(step.at * 1000))))
                guard !Task.isCancelled, let self else { return }
                self.perform(step.action)
            }
        }
    }

    func stop() {
        runTask?.cancel()
        levelTask?.cancel()
        settleTasks.values.forEach { $0.cancel() }
    }

    /// Resolves a script into a time-ordered list of primitive steps. Each hold
    /// advances the speaker to their next phrase-table line, so a script that
    /// never names its text still plays a coherent conversation in the demo's
    /// languages, and a `pair` event switches the languages mid-recording.
    static func expand(_ events: [DemoScriptEvent], phrasebook: DemoPhrasebook) -> [DemoStep] {
        var book = phrasebook
        var turns: [Side: Int] = [:]
        var currentLine: [Side: Int] = [.traveler: 0, .local: 1]
        var steps: [DemoStep] = []
        let ordered = events.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
        for event in ordered {
            let speaker = event.speaker
            let line = event.line ?? currentLine[speaker, default: 0]
            let captionKey = book.key(for: speaker.other)
            let sourceKey = book.key(for: speaker)
            switch event.event {
            case .hold:
                let turn = turns[speaker, default: 0]
                turns[speaker] = turn + 1
                currentLine[speaker] = event.line ?? (2 * turn + (speaker == .local ? 1 : 0))
                steps.append(DemoStep(at: event.at, action: .hold(speaker)))
            case .release:
                steps.append(DemoStep(at: event.at, action: .release(speaker)))
            case .text:
                steps.append(DemoStep(at: event.at, action: .caption(speaker, event.text ?? book.caption(line: line))))
            case .append:
                steps.append(DemoStep(at: event.at, action: .append(speaker, event.text ?? "")))
            case .stream:
                let chunks = streamChunks(event.text ?? book.caption(line: line), language: captionKey)
                steps += spread(chunks, from: event.at, over: event.duration) { .append(speaker, $0) }
            case .source:
                steps.append(DemoStep(at: event.at, action: .source(speaker, event.text ?? book.source(line: line))))
            case .streamSource:
                let chunks = streamChunks(event.text ?? book.source(line: line), language: sourceKey)
                steps += spread(chunks, from: event.at, over: event.duration) { .appendSource(speaker, $0) }
            case .state:
                if let state = translationState(named: event.state ?? event.text ?? "", speaker: speaker) {
                    steps.append(DemoStep(at: event.at, action: .state(speaker, state)))
                }
            case .pair:
                if let next = DemoPhrasebook(spec: event.pair ?? event.text ?? "") {
                    book = next
                    steps.append(DemoStep(at: event.at, action: .pair(next)))
                }
            }
        }
        return steps.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
    }

    /// Splits a line into the deltas a live caption arrives in: words where
    /// the script spaces words, a couple of characters at a time for Chinese,
    /// Japanese and Thai, which don't.
    static func streamChunks(_ text: String, language: String) -> [String] {
        let unspaced = ["ja", "zh", "th"].contains { language.hasPrefix($0) }
        var chunks: [String] = []
        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            let piece = String(word) + " "
            guard unspaced, word.count > 3 else {
                chunks.append(piece)
                continue
            }
            let size = language.hasPrefix("th") ? 3 : 2
            var remainder = Substring(piece)
            while !remainder.isEmpty {
                chunks.append(String(remainder.prefix(size)))
                remainder = remainder.dropFirst(size)
            }
        }
        if let last = chunks.popLast() {
            chunks.append(last.hasSuffix(" ") ? String(last.dropLast()) : last)
        }
        return chunks.filter { !$0.isEmpty }
    }

    private static func spread(
        _ chunks: [String], from start: Double, over duration: Double?, _ action: (String) -> DemoAction
    ) -> [DemoStep] {
        guard !chunks.isEmpty else { return [] }
        let span = duration ?? Double(chunks.count) * 0.22
        let gap = chunks.count > 1 ? span / Double(chunks.count - 1) : 0
        return chunks.enumerated().map { DemoStep(at: start + Double($0.offset) * gap, action: action($0.element)) }
    }

    private static func translationState(named name: String, speaker: Side) -> TranslationState? {
        switch name {
        case "armed": .armed(turn: speaker)
        case "listening": .listening(turn: speaker, level: 0)
        case "processing", "connecting": .processing(from: speaker)
        case "reconnecting": .reconnecting
        case "offline": .offline
        case "idle": .idle
        default: nil
        }
    }

    private func perform(_ action: DemoAction) {
        guard let stage else { return }
        switch action {
        case .hold(let speaker):
            if let other = holding, other != speaker { perform(.release(other)) }
            settleTasks[speaker]?.cancel()
            holding = speaker
            captions[speaker] = ""
            sources[speaker] = ""
            finished.remove(speaker)
            stage.demoHold(speaker)
            startLevels()
        case .release(let speaker):
            guard holding == speaker else { return }
            holding = nil
            stopLevels()
            stage.demoRelease(speaker)
            scheduleSettle(speaker)
        case .caption(let speaker, let text):
            captions[speaker] = text
            stage.demoCaption(text, speaker: speaker)
            scheduleSettle(speaker)
        case .append(let speaker, let chunk):
            let text = captions[speaker, default: ""] + chunk
            captions[speaker] = text
            stage.demoCaption(text, speaker: speaker)
            scheduleSettle(speaker)
        case .source(_, let text):
            stage.demoSource(text)
        case .appendSource(let speaker, let chunk):
            let text = sources[speaker, default: ""] + chunk
            sources[speaker] = text
            stage.demoSource(text)
        case .state(let speaker, let state):
            stage.demoState(state, speaker: speaker)
        case .pair(let book):
            stage.demoPair(book.pair)
        }
    }

    private func scheduleSettle(_ speaker: Side) {
        settleTasks[speaker]?.cancel()
        settleTasks[speaker] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, let self, self.holding != speaker,
                  !self.captions[speaker, default: ""].isEmpty, !self.finished.contains(speaker)
            else { return }
            self.finished.insert(speaker)
            self.stage?.demoTurnFinished(speaker)
        }
    }

    /// A speech-like level envelope for the aurora while someone "talks",
    /// standing in for the microphone the simulator doesn't have.
    private func startLevels() {
        levelTask?.cancel()
        levelTask = Task { [weak self] in
            let start = Date()
            while !Task.isCancelled, let stage = self?.stage {
                let t = Date().timeIntervalSince(start)
                let syllables = abs(sin(t * 6.3)) * (0.65 + 0.35 * sin(t * 1.7))
                stage.demoLevel(Float(0.25 + 0.5 * syllables))
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    private func stopLevels() {
        levelTask?.cancel()
        levelTask = nil
        stage?.demoLevel(0)
    }
}
#endif
