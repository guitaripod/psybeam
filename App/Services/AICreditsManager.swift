import Foundation
import AICreditsCore
import MidgarCore

/// Owns the AICredits client, which here only runs the app's AI calls (the account behind the mako api key that
/// `CreditsTranslationProvider` sends). It talks to mako through the gateway at `PsybeamMidgar.intelligenceURL`, so every
/// mako call, the app's own and AICredits', reaches `api.midgarcorp.cc`, metered against the Midgar ID's wallet. Its
/// purchase provider cannot buy, because the credit packs are sold by MidgarStore and MidgarCredits.
nonisolated final class AICreditsManager: Sendable {
    static let shared = AICreditsManager()

    let client: AICreditsClient
    let baseURL = PsybeamMidgar.intelligenceURL
    private let appID = PsybeamMidgar.appID

    private init() {
        let config = AICreditsConfig(
            baseURL: baseURL, appID: appID, lowBalanceThreshold: CreditsModel.lowBalanceThreshold,
            additionalHeaders: { await PsybeamMidgar.shared.midgarTokenHeaders() })
        client = AICreditsClient(config: config, purchaseProvider: HostManagedPurchaseProvider())
    }

    /// The api key of the old per-app account, which MidgarCredits sends as its legacy key so mako links the balance
    /// from before the move to the Midgar ID's wallet. The key lives in the keychain; a device that has none yet gets
    /// its account registered here, the same one the first AI call would register. Nil when that fails.
    func legacyAPIKey() async -> String? {
        try? await client.bootstrap().apiKey
    }
}

/// The purchase provider the AICredits client needs but never uses: it sells nothing, and every purchase attempt fails.
private nonisolated struct HostManagedPurchaseProvider: PurchaseProvider {
    func configure(appUserID: String) async {}
    func availablePackages() async throws -> [StorePackage] { [] }
    func purchase(packageID: String) async throws -> PurchaseReceipt {
        throw AICreditsError.purchaseFailed("Purchases are handled by the host app.")
    }
    func restore() async throws -> [RestoredEntitlement] { [] }
    func alias(to newAppUserID: String) async {}
}
