import Foundation
import AICreditsCore
import AICreditsRevenueCat
import AICreditsUI
import MidgarCore

/// Owns the AICredits client and the one `AICreditsStore` the screens read. The client talks to mako through the
/// gateway at `PsybeamMidgar.intelligenceURL`, so every mako call, the app's own and AICredits', reaches
/// `api.midgarcorp.cc`.
nonisolated final class AICreditsManager: Sendable {
    static let shared = AICreditsManager()

    static let lowBalanceThreshold = 5

    @MainActor static let store = AICreditsStore(
        client: AICreditsManager.shared.client, lowBalanceThreshold: lowBalanceThreshold)

    let client: AICreditsClient
    let baseURL = PsybeamMidgar.intelligenceURL
    private let appID = PsybeamMidgar.appID
    private let revenueCatPublicKey = "appl_MLWBSJBJGebbpfhFwNhhFDvvKfI"

    private init() {
        let config = AICreditsConfig(
            baseURL: baseURL, appID: appID, lowBalanceThreshold: Self.lowBalanceThreshold,
            additionalHeaders: { await PsybeamMidgar.shared.midgarTokenHeaders() })
        client = AICreditsClient(
            config: config,
            purchaseProvider: RevenueCatPurchaseProvider(apiKey: revenueCatPublicKey))
    }

    /// Reports the Apple Ads install attribution once per install, off the main
    /// actor. The result is logged token-free.
    func reportAdAttribution() {
        client.startAdAttributionReporting { result in
            MidgarLog.info("ad attribution \(result.logDescription)", category: .auth)
        }
    }
}
