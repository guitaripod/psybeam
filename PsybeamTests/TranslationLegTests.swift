import Combine
import PsybeamKit
import Testing
@testable import Psybeam

@MainActor
@Suite("TranslationLeg behavior")
struct TranslationLegTests {
    private func makeLeg(
        _ mock: MockCall,
        speaker: Side = .traveler,
        settleInterval: Duration = .milliseconds(120)
    ) -> TranslationLeg {
        TranslationLeg(
            call: mock,
            speaker: speaker,
            pair: LanguagePair(traveler: "en", local: "es"),
            settleInterval: settleInterval
        )
    }

    @Test("A successful hold arms the mic and reaches listening")
    func successListens() async {
        let mock = MockCall()
        let leg = makeLeg(mock)
        let states = Recorder(leg.statePublisher)
        leg.holdDown()
        let listening = await states.waitFor { if case .listening = $0 { return true }; return false }
        #expect(listening)
        #expect(mock.micActive)
    }

    @Test("Quota failure surfaces as quotaExhausted and never arms the mic")
    func quotaFailure() async {
        let mock = MockCall()
        mock.connectError = .quota
        let leg = makeLeg(mock)
        let states = Recorder(leg.statePublisher)
        leg.holdDown()
        let quota = await states.waitFor { $0 == .quotaExhausted }
        #expect(quota)
        #expect(!mock.micActive)
    }

    @Test("Unsupported language is named, not a generic retry")
    func unsupportedFailure() async {
        let mock = MockCall()
        mock.connectError = .unsupportedLanguage
        let leg = makeLeg(mock)
        let states = Recorder(leg.statePublisher)
        leg.holdDown()
        #expect(await states.waitFor { $0 == .error(.unsupportedLanguage) })
    }

    @Test("Output transcript accumulates into the caption; the closing delta fires finished")
    func outputRouting() async {
        let mock = MockCall()
        let leg = makeLeg(mock)
        let text = Recorder(leg.textPublisher)
        let finished = SignalRecorder(leg.finishedPublisher)
        // speaker is .traveler, so the translated OUTPUT side is .local
        mock.emit(TranscriptDelta(side: .local, text: "Hola", isFinal: false))
        mock.emit(TranscriptDelta(side: .local, text: " mundo", isFinal: true))
        #expect(await text.waitFor { $0 == "Hola mundo" })
        #expect(await finished.waitForSignal())
    }

    @Test("Source-side transcript routes to source, never the translation caption")
    func sourceRouting() async {
        let mock = MockCall()
        let leg = makeLeg(mock)
        let source = Recorder(leg.sourcePublisher)
        let text = Recorder(leg.textPublisher)
        // the INPUT side is the speaker (.traveler)
        mock.emit(TranscriptDelta(side: .traveler, text: "Where is it", isFinal: true))
        #expect(await source.waitFor { $0 == "Where is it" })
        let leaked = await text.waitFor(timeout: .milliseconds(200)) { $0.contains("Where is it") }
        #expect(!leaked)
    }

    @Test("A settled caption finishes the turn even though no closing delta ever arrives")
    func settlesWithoutFinalDelta() async {
        let mock = MockCall()
        let leg = makeLeg(mock)
        let finished = SignalRecorder(leg.finishedPublisher)
        let states = Recorder(leg.statePublisher)
        leg.holdDown()
        _ = await states.waitFor { if case .listening = $0 { return true }; return false }
        mock.emit(TranscriptDelta(side: .local, text: "Hola", isFinal: false))
        leg.holdUp()
        #expect(await finished.waitForSignal())
        try? await Task.sleep(for: .milliseconds(300))
        #expect(finished.signals == 1)
    }

    @Test("A turn still being held never finishes, however long the caption sits idle")
    func heldTurnNeverFinishes() async {
        let mock = MockCall()
        let leg = makeLeg(mock)
        let finished = SignalRecorder(leg.finishedPublisher)
        let states = Recorder(leg.statePublisher)
        leg.holdDown()
        _ = await states.waitFor { if case .listening = $0 { return true }; return false }
        mock.emit(TranscriptDelta(side: .local, text: "Hola", isFinal: false))
        #expect(!(await finished.waitForSignal(timeout: .milliseconds(400))))
    }

    @Test("A silent turn is never reported as delivered")
    func emptyTurnNeverFinishes() async {
        let mock = MockCall()
        let leg = makeLeg(mock)
        let finished = SignalRecorder(leg.finishedPublisher)
        let states = Recorder(leg.statePublisher)
        leg.holdDown()
        _ = await states.waitFor { if case .listening = $0 { return true }; return false }
        leg.holdUp()
        #expect(!(await finished.waitForSignal(timeout: .milliseconds(400))))
    }

    @Test("Each hold finishes its own turn")
    func consecutiveTurnsEachFinish() async {
        let mock = MockCall()
        let leg = makeLeg(mock)
        let finished = SignalRecorder(leg.finishedPublisher)
        let states = Recorder(leg.statePublisher)
        var expected = 0
        for text in ["Hola", "Adiós"] {
            expected += 1
            leg.holdDown()
            _ = await states.waitFor { if case .listening = $0 { return true }; return false }
            mock.emit(TranscriptDelta(side: .local, text: text, isFinal: false))
            leg.holdUp()
            #expect(await waitUntil { finished.signals >= expected })
        }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(finished.signals == 2)
    }

    @Test("Releasing the hold turns the mic off")
    func releaseStopsMic() async {
        let mock = MockCall()
        let leg = makeLeg(mock)
        let states = Recorder(leg.statePublisher)
        leg.holdDown()
        _ = await states.waitFor { if case .listening = $0 { return true }; return false }
        #expect(mock.micActive)
        leg.holdUp()
        #expect(await waitUntil { !mock.micActive })
    }
}
