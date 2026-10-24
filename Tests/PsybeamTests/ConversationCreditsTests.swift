import Foundation
import MidgarCredits
import PsybeamCore
import SwiftUI
import Testing
import UIKit
@testable import Psybeam

/// How the conversation screen reaches the credit store and follows the balance, with the wallet scripted and the screen
/// shown in a window of its own.
@MainActor
@Suite(.serialized)
struct ConversationCreditsTests {
    private struct NoSessions: TranslationProviding {
        func requestSession(pair: LanguagePair, direction: Side) async throws -> SessionToken {
            throw CancellationError()
        }

        func reportUsage(sessionId: String, secondsUsed: Int) async {}
    }

    private struct Screen {
        let conversation: ConversationViewController
        let window: UIWindow
    }

    private func show(credits: CreditsModel) throws -> Screen {
        let viewModel = ConversationViewModel(
            travelerCall: RealtimeCallService(translationProvider: NoSessions()),
            localCall: RealtimeCallService(translationProvider: NoSessions()))
        let conversation = ConversationViewController(viewModel: viewModel, credits: credits)
        conversation.loadViewIfNeeded()
        conversation.needsConsentOnAppear = false
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = conversation
        window.makeKeyAndVisible()
        return Screen(conversation: conversation, window: window)
    }

    private func presentedStore(of screen: Screen) -> UIHostingController<CreditStoreSheet>? {
        screen.conversation.presentedViewController as? UIHostingController<CreditStoreSheet>
    }

    @Test func runningOutOfMinutesOpensTheCreditStoreWithoutAShortfall() throws {
        let screen = try show(credits: CreditsModel(source: ScriptedWallet(credits: 0)))

        screen.conversation.render(legState: .quotaExhausted, speaker: .traveler)

        let store = try #require(presentedStore(of: screen))
        #expect(store.rootView.shortfall == nil)
        #expect(screen.conversation.knownBalance == 0)
        screen.window.isHidden = true
    }

    @Test func aCallThatReportsAShortfallOpensTheStoreWithIt() throws {
        let screen = try show(credits: CreditsModel(source: ScriptedWallet(credits: 1)))

        screen.conversation.presentStoreIfPossible(shortfall: 7)

        let store = try #require(presentedStore(of: screen))
        #expect(store.rootView.shortfall == 7)
        screen.window.isHidden = true
    }

    @Test func tappingTheNoticeOpensTheStoreOnce() throws {
        let screen = try show(credits: CreditsModel(source: ScriptedWallet(credits: 2)))

        screen.conversation.noticeButton.sendActions(for: .touchUpInside)
        let first = try #require(presentedStore(of: screen))
        screen.conversation.noticeButton.sendActions(for: .touchUpInside)

        #expect(screen.conversation.presentedViewController === first)
        screen.window.isHidden = true
    }

    @Test func aHostWithoutAWalletOpensNoStore() throws {
        let screen = try show(credits: CreditsModel(source: nil))

        screen.conversation.render(legState: .quotaExhausted, speaker: .traveler)

        #expect(screen.conversation.presentedViewController == nil)
        screen.window.isHidden = true
    }

    @Test func theKnownBalanceFollowsTheModelOnceItWasRead() async throws {
        let wallet = ScriptedWallet(credits: 9)
        let credits = CreditsModel(source: wallet)
        let screen = try show(credits: credits)
        screen.conversation.knownBalance = 9
        let following = Task { await credits.start() }
        #expect(await eventually { credits.balance == 9 })

        await wallet.emit(.balanceChanged(MidgarCreditsBalance(credits: 2, updatedAt: Date())))

        #expect(await eventually { screen.conversation.knownBalance == 2 })
        following.cancel()
        screen.window.isHidden = true
    }

    @Test func theBalanceStaysUnknownUntilTheWalletAnswers() async throws {
        let wallet = ScriptedWallet(credits: 9)
        await wallet.set(credits: 9, failing: true)
        let screen = try show(credits: CreditsModel(source: wallet))

        screen.conversation.refreshBalance()
        try? await Task.sleep(for: .milliseconds(200))

        #expect(screen.conversation.knownBalance == nil)
        screen.window.isHidden = true
    }
}
