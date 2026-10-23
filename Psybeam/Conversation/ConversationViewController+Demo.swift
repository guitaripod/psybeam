import PsybeamKit
import MidgarCore
import UIKit

extension ConversationViewController {
    /// DEBUG-only screenshot and recording modes, selected by `PSYBEAM_DEMO`
    /// and documented in `marketing/video/README.md`. Every mode renders
    /// through the production paths and persists nothing.
    @discardableResult
    func applyPreviewIfNeeded() -> Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let uiLanguage = Bundle.main.preferredLocalizations.first ?? "en"
        guard let demo = DemoConfiguration(environment: environment, uiLanguage: uiLanguage) else { return false }
        self.demo = demo
        convoRoot.alpha = 1
        firstRun = demo.initialStage
        viewModel.showDemoPair(demo.phrasebook.pair)
        updateLanguages(demo.phrasebook.pair)
        switch demo.mode {
        case "listening":
            showDemoTurn(line: 0, finished: false)
        case "them":
            showDemoTurn(line: 1, finished: false)
        case "coach-theirs":
            showDemoTurn(line: 0, finished: true)
        default:
            refreshResting()
        }
        visualizer.setLevel(demo.level ?? (["listening", "them", "settings", "consent"].contains(demo.mode) ? 0.6 : 0))
        let mode = demo.mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.presentDemoSheet(for: mode) }
        return true
        #else
        return false
        #endif
    }
}

#if DEBUG
extension ConversationViewController: DemoStage {
    func demoHold(_ speaker: Side) {
        talkButton(for: speaker).setActive(true)
        beginHold(speaker)
        handleText("", speaker: speaker)
        sourceLabel.text = ""
        render(legState: .listening(turn: speaker, level: 0), speaker: speaker)
    }

    func demoRelease(_ speaker: Side) {
        talkButton(for: speaker).setActive(false)
        render(legState: .idle, speaker: speaker)
        endHold()
    }

    func demoCaption(_ text: String, speaker: Side) {
        handleText(text, speaker: speaker)
    }

    func demoSource(_ text: String) {
        sourceLabel.text = text
    }

    func demoState(_ state: TranslationState, speaker: Side) {
        render(legState: state, speaker: speaker)
    }

    func demoPair(_ pair: LanguagePair) {
        showDemoPair(pair)
    }

    func demoLevel(_ level: Float) {
        visualizer.setLevel(level)
    }

    func demoTurnFinished(_ speaker: Side) {
        onTurnFinished(speaker)
    }

    func showDemoPair(_ pair: LanguagePair) {
        viewModel.showDemoPair(pair)
        updateLanguages(pair)
    }

    func talkButton(for speaker: Side) -> TalkButton {
        speaker == .traveler ? meButton : themButton
    }

    /// A still of one phrase-table line mid-turn (the button held, the caption
    /// facing its listener), or finished and released when `finished`.
    func showDemoTurn(line: Int, finished: Bool) {
        guard let book = demo?.phrasebook else { return }
        let speaker = DemoPhrasebook.speaker(ofLine: line)
        demoHold(speaker)
        demoSource(book.source(line: line))
        demoCaption(book.caption(line: line), speaker: speaker)
        guard finished else { return }
        demoRelease(speaker)
        demoTurnFinished(speaker)
    }

    func presentDemoSheet(for mode: String) {
        switch mode {
        case "settings": openSettings()
        case "consent": presentConsent()
        case "destination": presentDestinationPicker()
        default: break
        }
    }

    func startDebugPressIfNeeded() {
        if LaunchOverrides.current.locationOffer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.presentLocationOffer() }
        }
        guard let side = LaunchOverrides.current.press else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in _ = self?.pressBegan(side) }
    }

    func startDemoScriptIfNeeded() {
        guard let demo, demo.mode == "script", demoPlayer == nil else { return }
        let player = DemoScriptPlayer(events: demo.script, phrasebook: demo.phrasebook, stage: self)
        demoPlayer = player
        player.start()
    }
}
#endif
