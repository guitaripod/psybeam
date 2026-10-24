import Foundation
import MidgarCommerce
import MidgarCore
import MidgarCredits
import StoreKitTest
import Testing
import UIKit
@testable import Psybeam

extension GatewayBacked {
    /// Buys Psybeam's credit packs through MidgarCredits on a MidgarStore with the app's own configuration, against
    /// `Products.storekit` (the file the scheme runs with), so the pack table, the StoreKit products and mako's validate
    /// request are checked together on a real StoreKit. The gateway is a `URLProtocol` stub, so nothing reaches mako.
    /// StoreKit is process-wide, so the suite runs serially. A test session signs its transactions with Xcode's local
    /// certificate, so the store never reports them to the ledger. The first purchase on a fresh simulator can stall:
    /// rerun once.
    @MainActor
    @Suite(.timeLimit(.minutes(3)))
    struct Purchases {
        private nonisolated static let legacyKey = "legacy-aicredits-key"
        private static let smallProductID = "com.guitaripod.psybeam.credits.small"

        private struct Harness {
            let store: MidgarStore
            let credits: MidgarCredits
            let model: CreditsModel
            let session: SKTestSession
            let directory: URL

            func stop() async {
                await credits.stop()
                await store.stop()
                try? FileManager.default.removeItem(at: directory)
            }
        }

        private static let configurationURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Products.storekit")

        private func makeHarness(purchasing override: (any MidgarCreditsPurchasing)? = nil) throws -> Harness {
            let session = try SKTestSession(contentsOf: Self.configurationURL)
            session.resetToDefaultState()
            session.clearTransactions()
            session.disableDialogs = true
            session.askToBuyEnabled = false
            GatewayStub.reset()
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("psybeam-credits-" + UUID().uuidString, isDirectory: true)
            let configuration = GatewayStub.httpConfiguration()
            let identity = StubIdentity()
            let store = MidgarStore(
                configuration: PsybeamPacks.storeConfiguration(directory: directory),
                identity: identity,
                http: MidgarHTTPClient(configuration: configuration)
            )
            let credits = MidgarCredits(
                configuration: PsybeamPacks.creditsConfiguration(directory: directory),
                http: configuration,
                identity: identity,
                purchasing: override ?? SceneAnchoredPurchasing(store: store),
                legacyAPIKey: { Self.legacyKey }
            )
            return Harness(store: store, credits: credits, model: CreditsModel(source: credits), session: session, directory: directory)
        }

        @Test func theConfigurationFileSellsExactlyTheThreePacksAtTheirPrices() throws {
            let file = try JSONDecoder().decode(StoreKitFile.self, from: Data(contentsOf: Self.configurationURL))
            let sold = Dictionary(uniqueKeysWithValues: file.products.map { ($0.productID, $0) })

            #expect(Set(sold.keys) == Set(PsybeamPacks.productIDs))
            #expect(sold.values.allSatisfy { $0.type == "Consumable" })
            #expect(sold["com.guitaripod.psybeam.credits.small"]?.displayPrice == "4.99")
            #expect(sold["com.guitaripod.psybeam.credits.medium"]?.displayPrice == "9.99")
            #expect(sold["com.guitaripod.psybeam.credits.large"]?.displayPrice == "19.99")
            #expect(sold["com.guitaripod.psybeam.credits.small"]?.referenceName == "Small")
            #expect(sold["com.guitaripod.psybeam.credits.medium"]?.referenceName == "Medium")
            #expect(sold["com.guitaripod.psybeam.credits.large"]?.referenceName == "Large")
        }

        @Test func thePackTableMatchesMakosCatalog() {
            #expect(PsybeamPacks.all.map(\.id) == ["small", "medium", "large"])
            #expect(PsybeamPacks.all.map(\.credits) == [45, 120, 300])
            #expect(PsybeamPacks.all.allSatisfy { $0.productID == "com.guitaripod.psybeam.credits." + $0.id })
            #expect(PsybeamPacks.creditsConfiguration().productIDs == PsybeamPacks.productIDs)
            #expect(PsybeamPacks.storeConfiguration().productIDs == PsybeamPacks.productIDs)
            #expect(PsybeamPacks.storeConfiguration().entitlementsByProduct.isEmpty)
            #expect(PsybeamPacks.storeConfiguration().mode == .purchases)
            #expect(PsybeamPacks.storeConfiguration().appID == "psybeam")
        }

        @Test func theOffersAreTheThreePacksWithStoreKitsPrices() async throws {
            let harness = try makeHarness()

            let offers = try await harness.credits.offers()

            #expect(offers.map(\.pack.id) == ["small", "medium", "large"])
            #expect(offers.map(\.product.displayPrice) == ["$4.99", "$9.99", "$19.99"])
            #expect(offers.map(\.product.displayName) == ["Small", "Medium", "Large"])
            await harness.stop()
        }

        @Test func buyingSmallCarriesTheMidgarIDAndPostsMakosValidateRoute() async throws {
            let harness = try makeHarness()
            GatewayStub.setBalance(3)
            let observing = Task { await harness.model.start() }
            #expect(await eventually { harness.model.balance == 3 })
            GatewayStub.setBalance(48)
            GatewayStub.setValidate([.credited(added: 45, newBalance: 48)])

            let result = try await harness.credits.buy("small")

            #expect(result == .credited(packID: "small", creditsAdded: 45, balance: 48))
            let bought = harness.session.allTransactions().filter { $0.productIdentifier == Self.smallProductID }
            let transaction = try #require(bought.first)
            #expect(bought.count == 1)
            let posted = GatewayStub.requests(method: "POST", pathSuffix: "/v1/credits/purchase/revenuecat/validate")
            let request = try #require(posted.first)
            #expect(posted.count == 1)
            let body = try request.json()
            #expect(body["pack_id"] == "small")
            #expect(body["product_id"] == Self.smallProductID)
            #expect(body["purchase_token"] == String(transaction.identifier))
            #expect(body["platform"] == "ios")
            let signed = try SignedTransactionPayload(jws: try #require(body["signed_transaction"]))
            #expect(signed.transactionId == String(transaction.identifier))
            #expect(signed.productId == Self.smallProductID)
            #expect(signed.appAccountToken?.uppercased() == StubIdentity.midgarID)
            #expect(request.header("X-App-ID") == "psybeam")
            #expect(request.header("Authorization") == "Bearer " + Self.legacyKey)
            #expect(request.header("X-Midgar-Token") == StubIdentity.accessToken)
            #expect(await eventually { harness.model.balance == 48 })
            #expect(await harness.credits.unconfirmedPurchases == 0)
            observing.cancel()
            await harness.stop()
        }

        @Test func aCreditPendingAnswerKeepsTheReceiptAndALaterRefreshCreditsIt() async throws {
            let harness = try makeHarness()
            GatewayStub.setBalance(3)
            GatewayStub.setValidate([.error(status: 409, code: "credit_pending", message: "The credit is on its way.")])

            let result = try await harness.credits.buy("small")

            #expect(result == .creditPending(packID: "small", credits: 45))
            #expect(await harness.credits.unconfirmedPurchases == 1)
            let validations = GatewayStub.requests(method: "POST", pathSuffix: "/v1/credits/purchase/revenuecat/validate")
            let transactionIDs = try Set(validations.map { try $0.json()["purchase_token"] })
            #expect(validations.count == 4)
            #expect(transactionIDs.count == 1)
            let kept = try Data(contentsOf: harness.directory.appendingPathComponent("credits-psybeam.json"))
            #expect(String(decoding: kept, as: UTF8.self).contains(Self.smallProductID))

            GatewayStub.setBalance(48)
            GatewayStub.setValidate([.credited(added: 45, newBalance: 48)])
            let balance = try await harness.credits.refresh()

            #expect(balance.credits == 48)
            #expect(await harness.credits.unconfirmedPurchases == 0)
            let retried = GatewayStub.requests(method: "POST", pathSuffix: "/v1/credits/purchase/revenuecat/validate")
            #expect(retried.count == 5)
            #expect(try Set(retried.map { try $0.json()["purchase_token"] }) == transactionIDs)
            await harness.stop()
        }

        @Test func aCancelledPurchaseCreditsNothingAndPostsNothing() async throws {
            let harness = try makeHarness(purchasing: CancellingPurchasing())

            let result = try await harness.credits.buy("small")

            #expect(result == .cancelled)
            #expect(GatewayStub.requests(method: "POST", pathSuffix: "/v1/credits/purchase/revenuecat/validate").isEmpty)
            #expect(await harness.credits.unconfirmedPurchases == 0)
            await harness.stop()
        }

        @Test func aStoreKitFailureThrowsAndPostsNothing() async throws {
            let harness = try makeHarness()
            try await harness.session.setSimulatedError(.generic(.unknown), forAPI: .purchase)

            await #expect(throws: MidgarCreditsError.self) {
                _ = try await harness.credits.buy("small")
            }

            #expect(GatewayStub.requests(method: "POST", pathSuffix: "/v1/credits/purchase/revenuecat/validate").isEmpty)
            #expect(await harness.credits.unconfirmedPurchases == 0)
            #expect(harness.session.allTransactions().isEmpty)
            await harness.stop()
        }

        @Test func anUnknownPackIsRefusedBeforeStoreKitIsAsked() async throws {
            let harness = try makeHarness()

            await #expect(throws: MidgarCreditsError.self) {
                _ = try await harness.credits.buy("huge")
            }

            #expect(GatewayStub.requests(method: "POST", pathSuffix: "/v1/credits/purchase/revenuecat/validate").isEmpty)
            #expect(harness.session.allTransactions().isEmpty)
            await harness.stop()
        }
    }
}

/// The store with every purchase confirmed in the host app's window scene, as StoreKit needs inside a test host: a
/// scene-less purchase there never completes, because StoreKit finds no window to confirm in. Everything else is the
/// store itself, and MidgarCredits sells through this exactly as it sells through the store.
private nonisolated struct SceneAnchoredPurchasing: MidgarCreditsPurchasing {
    let store: MidgarStore

    func products() async throws -> [StoreProduct] {
        try await store.products()
    }

    func purchaseReceipt(_ productID: String) async throws -> MidgarReceiptResult {
        try await purchase(productID, in: store)
    }

    func events() async -> AsyncStream<MidgarStoreEvent> {
        await store.events()
    }

    @MainActor
    private func purchase(_ productID: String, in store: MidgarStore) async throws -> MidgarReceiptResult {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw MidgarStoreError.unsupportedPlatform
        }
        return try await store.purchaseReceipt(productID, confirmIn: scene)
    }
}

/// The customer dismissing the purchase sheet. StoreKitTest cannot script that (a simulated `userCancelled` error
/// surfaces as a StoreKit failure, not as the `userCancelled` result), so the store answers `.cancelled` itself, which is
/// what MidgarStore returns for the real result. Nothing is bought and StoreKit is not asked.
private nonisolated struct CancellingPurchasing: MidgarCreditsPurchasing {
    func products() async throws -> [StoreProduct] { [] }

    func purchaseReceipt(_ productID: String) async throws -> MidgarReceiptResult { .cancelled }

    func events() async -> AsyncStream<MidgarStoreEvent> { AsyncStream { _ in } }
}

/// The claims of a signed transaction the validate request carries, read from the JWS payload.
private nonisolated struct SignedTransactionPayload: Decodable {
    let transactionId: String
    let productId: String
    let appAccountToken: String?

    init(jws: String) throws {
        let parts = jws.split(separator: ".")
        guard parts.count == 3 else {
            throw URLError(.cannotParseResponse)
        }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else {
            throw URLError(.cannotDecodeContentData)
        }
        self = try JSONDecoder().decode(SignedTransactionPayload.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case transactionId
        case productId
        case appAccountToken
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactionId = try container.decode(String.self, forKey: .transactionId)
        productId = try container.decode(String.self, forKey: .productId)
        appAccountToken = try container.decodeIfPresent(String.self, forKey: .appAccountToken)
    }
}

/// The parts of a StoreKit configuration file the product check reads.
private nonisolated struct StoreKitFile: Decodable {
    struct Item: Decodable {
        let productID: String
        let displayPrice: String
        let referenceName: String
        let type: String
    }

    let products: [Item]
}
