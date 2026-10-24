#if DEBUG
import Foundation
import MidgarCommerce
import MidgarCredits
import MidgarCreditsUI

/// The wallet of a demo capture: the free-tier grant of a new account as a fixed balance, the three packs at their store
/// prices and no network. A simulator can never pass the App Attest check mako's identity endpoint requires, so the live
/// balance would read 0 there. Buying does nothing, so a capture can never charge anything.
nonisolated struct DemoCreditsSource: MidgarCreditStoreSource {
    var balance: MidgarCreditsBalance? {
        get async { Self.fixedBalance }
    }

    var unconfirmedPurchases: Int {
        get async { 0 }
    }

    func refresh() async throws -> MidgarCreditsBalance {
        Self.fixedBalance
    }

    func offers() async throws -> [MidgarCreditsOffer] {
        PsybeamPacks.all.compactMap { pack in
            Self.storeListing[pack.id].map { name, price in
                MidgarCreditsOffer(
                    pack: pack,
                    product: StoreProduct(id: pack.productID, displayName: name, description: "", displayPrice: price)
                )
            }
        }
    }

    func buy(_ packID: String) async throws -> MidgarCreditsPurchaseResult {
        .cancelled
    }

    func events() async -> AsyncStream<MidgarCreditsEvent> {
        AsyncStream { _ in }
    }

    private static let storeListing = [
        PsybeamPacks.small.id: ("Small", "$4.99"),
        PsybeamPacks.medium.id: ("Medium", "$9.99"),
        PsybeamPacks.large.id: ("Large", "$19.99")
    ]

    private static var fixedBalance: MidgarCreditsBalance {
        MidgarCreditsBalance(credits: DemoConfiguration.freeMinutesGrant, updatedAt: Date())
    }
}
#endif
