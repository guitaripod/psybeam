import Foundation
import PsybeamKit
import Testing
@testable import Psybeam

@MainActor
@Suite("Language pair persistence", .serialized)
struct LanguagePersistenceTests {
    private static let keys = ["psybeam.travelerLanguage", "psybeam.localLanguage"]

    private struct NoSessions: TranslationProviding {
        func requestSession(pair: LanguagePair, direction: Side) async throws -> SessionToken {
            throw CancellationError()
        }

        func reportUsage(sessionId: String, secondsUsed: Int) async {}
    }

    /// Runs `body` against the given stored languages, then puts back whatever
    /// the host app had stored.
    private func withStoredLanguages(traveler: String?, local: String?, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let saved = Self.keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(Self.keys, saved) { defaults.set(value, forKey: key) } }
        defaults.set(traveler, forKey: Self.keys[0])
        defaults.set(local, forKey: Self.keys[1])
        body()
    }

    /// A fresh view model reads the stored pair exactly as a relaunch would.
    private func relaunch() -> ConversationViewModel {
        ConversationViewModel(
            travelerCall: RealtimeCallService(translationProvider: NoSessions()),
            localCall: RealtimeCallService(translationProvider: NoSessions()))
    }

    @Test("Changing your language keeps the destination you saw after a relaunch")
    func travelerChangeKeepsDestination() {
        withStoredLanguages(traveler: "es", local: nil) {
            let viewModel = relaunch()
            #expect(viewModel.pair == LanguagePair(traveler: "es", local: "en"))
            viewModel.setTravelerLanguage("de")
            #expect(viewModel.pair == LanguagePair(traveler: "de", local: "en"))
            #expect(relaunch().pair == viewModel.pair)
        }
    }

    @Test("A repaired same-language pair keeps its destination when your language changes")
    func repairedPairKeepsDestination() {
        withStoredLanguages(traveler: "en", local: "en") {
            let viewModel = relaunch()
            #expect(viewModel.pair == LanguagePair(traveler: "en", local: "es"))
            viewModel.setTravelerLanguage("de")
            #expect(relaunch().pair == LanguagePair(traveler: "de", local: "es"))
        }
    }

    @Test("Choosing your own language as theirs swaps, and the swap survives a relaunch")
    func swapOnCollisionPersists() {
        withStoredLanguages(traveler: "en", local: "ja") {
            let viewModel = relaunch()
            viewModel.setLocalLanguage("en")
            #expect(viewModel.pair == LanguagePair(traveler: "ja", local: "en"))
            #expect(relaunch().pair == LanguagePair(traveler: "ja", local: "en"))
        }
    }
}
