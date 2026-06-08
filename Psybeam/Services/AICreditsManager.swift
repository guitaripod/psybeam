import Foundation
import AICreditsCore
import AICreditsRevenueCat
import AICreditsUI

final class AICreditsManager: Sendable {
    static let shared = AICreditsManager()

    @MainActor static let store = AICreditsStore(
        client: AICreditsManager.shared.client, lowBalanceThreshold: 5)

    let client: AICreditsClient
    let baseURL = URL(string: "https://openai-image-proxy.guitaripod.workers.dev")!
    private let appID = "psybeam"
    private let revenueCatPublicKey = "appl_MLWBSJBJGebbpfhFwNhhFDvvKfI"

    private init() {
        let config = AICreditsConfig(baseURL: baseURL, appID: appID, lowBalanceThreshold: 5)
        client = AICreditsClient(
            config: config,
            purchaseProvider: RevenueCatPurchaseProvider(apiKey: revenueCatPublicKey))
    }
}
