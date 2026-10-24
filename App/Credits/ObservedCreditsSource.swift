import MidgarCore
import MidgarCredits
import MidgarCreditsUI

/// The wallet as the credit store sees it, with one addition: a purchase that fails is logged and held against the
/// review prompt, as the app always did. Everything else is the wallet itself.
nonisolated struct ObservedCreditsSource: MidgarCreditStoreSource {
    let wallet: any MidgarCreditStoreSource
    let purchaseFailed: @Sendable (any Error) -> Void

    var balance: MidgarCreditsBalance? {
        get async { await wallet.balance }
    }

    var unconfirmedPurchases: Int {
        get async { await wallet.unconfirmedPurchases }
    }

    func refresh() async throws -> MidgarCreditsBalance {
        try await wallet.refresh()
    }

    func offers() async throws -> [MidgarCreditsOffer] {
        try await wallet.offers()
    }

    func buy(_ packID: String) async throws -> MidgarCreditsPurchaseResult {
        do {
            return try await wallet.buy(packID)
        } catch {
            purchaseFailed(error)
            throw error
        }
    }

    func events() async -> AsyncStream<MidgarCreditsEvent> {
        await wallet.events()
    }

    /// What the running app does with a failed purchase: writes it to the file log and holds the review prompt back.
    static func recordPurchaseFailure(_ error: any Error) {
        MidgarLog.error("credits error: \(error.localizedDescription)", category: .auth)
        ReviewPrompt.notePurchaseFailure()
    }
}
