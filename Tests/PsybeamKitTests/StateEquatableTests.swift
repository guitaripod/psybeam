import Testing
@testable import PsybeamKit

@Suite("State equatable")
struct StateEquatableTests {
    @Test("CallState distinguishes live turns")
    func callStateTurns() {
        #expect(CallState.live(turn: .traveler) == .live(turn: .traveler))
        #expect(CallState.live(turn: .traveler) != .live(turn: .local))
        #expect(CallState.idle != .connecting)
    }

    @Test("CallState.failed compares its error payload")
    func callStateFailure() {
        #expect(CallState.failed(.network) == .failed(.network))
        #expect(CallState.failed(.network) != .failed(.cancelled))
        #expect(CallState.failed(.permission(.microphone)) != .failed(.permission(.location)))
    }

    @Test("TranslationState compares associated values")
    func translationStateAssociated() {
        #expect(TranslationState.listening(turn: .local, level: 0.5) == .listening(turn: .local, level: 0.5))
        #expect(TranslationState.listening(turn: .local, level: 0.5) != .listening(turn: .local, level: 0.6))
        #expect(TranslationState.speaking(to: .traveler, isReplay: false) != .speaking(to: .traveler, isReplay: true))
        #expect(TranslationState.passthrough(side: .local) == .passthrough(side: .local))
    }

    @Test("TranslationState distinguishes denied permissions and errors")
    func translationStateFailures() {
        #expect(TranslationState.permissionDenied(.microphone) != .permissionDenied(.location))
        #expect(TranslationState.error(.quota) == .error(.quota))
        #expect(TranslationState.error(.server("boom")) != .error(.server("bang")))
        #expect(TranslationState.quotaExhausted != .offline)
    }

    @Test("Side.other flips the active direction")
    func sideOther() {
        #expect(Side.traveler.other == .local)
        #expect(Side.local.other == .traveler)
    }

    @Test("LanguagePair output language follows the active direction")
    func pairOutput() {
        let pair = LanguagePair(traveler: "en", local: "ja")
        #expect(pair.outputLanguage(for: .traveler) == "ja")
        #expect(pair.outputLanguage(for: .local) == "en")
    }
}
