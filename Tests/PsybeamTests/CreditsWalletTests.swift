import Foundation
import MidgarCommerce
import MidgarCore
import MidgarCredits
import Testing
import os
@testable import Psybeam

extension GatewayBacked {
    /// What the wallet does for Psybeam besides buying: deleting the old account, reporting the Apple Ads install, and
    /// the balance read after a realtime session settles. All against the gateway stub, so nothing reaches mako.
    @MainActor
    @Suite
    struct Wallet {
        private nonisolated static let attributionToken = "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo="

        private nonisolated struct FixedToken: MidgarAdAttributionTokenProviding {
            func attributionToken() throws -> String? { Wallet.attributionToken }
        }

        private struct SettleBody: Decodable {
            let session_id: String
            let minutes_used: Int
        }

        private func makeCredits(
            legacyKey: String?,
            configuration: MidgarCreditsConfiguration? = nil
        ) -> (credits: MidgarCredits, directory: URL) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("psybeam-wallet-" + UUID().uuidString, isDirectory: true)
            let credits = MidgarCredits(
                configuration: configuration ?? PsybeamPacks.creditsConfiguration(directory: directory),
                http: GatewayStub.httpConfiguration(),
                identity: StubIdentity(),
                purchasing: NoPurchasing(),
                legacyAPIKey: { legacyKey }
            )
            return (credits, directory)
        }

        @Test func deletingTheAccountSendsTheLegacyKeyAloneAndThenForgetsTheLocalIdentity() async throws {
            GatewayStub.reset()
            let (credits, directory) = makeCredits(legacyKey: "legacy-key")
            let service = AccountService(client: AICreditsManager.shared.client, credits: credits)

            try await service.deleteAccount()

            let deletes = GatewayStub.requests(method: "DELETE", pathSuffix: "/v1/identity")
            let request = try #require(deletes.first)
            #expect(deletes.count == 1)
            #expect(request.header("Authorization") == "Bearer legacy-key")
            #expect(request.header("X-Midgar-Token") == nil)
            #expect(request.header("X-App-ID") == "psybeam")
            await credits.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        @Test func aFailedDeletionThrowsSoNothingLocalIsErased() async throws {
            GatewayStub.reset()
            GatewayStub.setLegacyDelete(.error(status: 503, code: "wallet_unavailable", message: "The wallet is unavailable."))
            let (credits, directory) = makeCredits(legacyKey: "legacy-key")
            let service = AccountService(client: AICreditsManager.shared.client, credits: credits)

            await #expect(throws: AccountService.AccountError.self) {
                try await service.deleteAccount()
            }

            #expect(GatewayStub.requests(method: "DELETE", pathSuffix: "/v1/identity").count == 1)
            await credits.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        @Test func theInstallIsReportedOnceWithTheLegacyKeyAndTheMidgarToken() async throws {
            GatewayStub.reset()
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("psybeam-wallet-" + UUID().uuidString, isDirectory: true)
            let configuration = PsybeamPacks.creditsConfiguration(
                directory: directory, attributionTokenProvider: FixedToken(), isProductionLaunch: { true })
            let (credits, _) = makeCredits(legacyKey: "legacy-key", configuration: configuration)

            let first = await credits.reportAdAttributionOnce()
            let second = await credits.reportAdAttributionOnce()

            #expect(first == .settled(.attributed))
            #expect(second == .alreadySettled(.attributed))
            let posts = GatewayStub.requests(method: "POST", pathSuffix: "/v1/attribution")
            let request = try #require(posts.first)
            #expect(posts.count == 1)
            #expect(try request.json()["attribution_token"] == Self.attributionToken)
            #expect(request.header("Authorization") == "Bearer legacy-key")
            #expect(request.header("X-Midgar-Token") == StubIdentity.accessToken)
            #expect(request.header("X-App-ID") == "psybeam")
            await credits.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        @Test func aDebugBuildOrTestHostReportsNoInstall() async {
            GatewayStub.reset()
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("psybeam-wallet-" + UUID().uuidString, isDirectory: true)
            let configuration = PsybeamPacks.creditsConfiguration(directory: directory, attributionTokenProvider: FixedToken())
            let (credits, _) = makeCredits(legacyKey: "legacy-key", configuration: configuration)

            let result = await credits.reportAdAttributionOnce()

            #expect(PsybeamMidgar.isProductionLaunch == false)
            #expect(result == .skipped)
            #expect(GatewayStub.requests(method: "POST", pathSuffix: "/v1/attribution").isEmpty)
            await credits.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        @Test func aSettledSessionReadsTheBalanceAgain() async throws {
            GatewayStub.reset()
            let settled = Counter()
            let provider = CreditsTranslationProvider(
                apiKey: { "legacy-key" },
                gateway: stubGateway(),
                onSettled: { settled.increment() })

            await provider.reportUsage(sessionId: "rt_1", secondsUsed: 61)

            let posts = GatewayStub.requests(method: "POST", pathSuffix: "/v1/run/realtime.translate/settle")
            let request = try #require(posts.first)
            let body = try JSONDecoder().decode(SettleBody.self, from: request.body)
            #expect(posts.count == 1)
            #expect(body.session_id == "rt_1")
            #expect(body.minutes_used == 2)
            #expect(request.header("Authorization") == "Bearer legacy-key")
            #expect(settled.value == 1)
        }

        @Test func aSettleThatFailsDoesNotReadTheBalance() async {
            GatewayStub.reset()
            GatewayStub.setSettle(.error(status: 500, code: "server", message: "down"))
            let settled = Counter()
            let provider = CreditsTranslationProvider(
                apiKey: { "legacy-key" },
                gateway: stubGateway(),
                onSettled: { settled.increment() })

            await provider.reportUsage(sessionId: "rt_2", secondsUsed: 30)

            #expect(GatewayStub.requests(method: "POST", pathSuffix: "/v1/run/realtime.translate/settle").count == 1)
            #expect(settled.value == 0)
        }

        private func stubGateway() -> MakoGateway {
            MakoGateway(
                client: MidgarHTTPClient(configuration: GatewayStub.httpConfiguration()),
                midgarHeaders: { ["X-Midgar-Token": StubIdentity.accessToken] })
        }
    }
}

/// Counts how often a callback ran, from any isolation.
private nonisolated final class Counter: Sendable {
    private let count = OSAllocatedUnfairLock(initialState: 0)

    func increment() {
        count.withLock { $0 += 1 }
    }

    var value: Int {
        count.withLock { $0 }
    }
}

/// A store that sells nothing, for a wallet that only reads, deletes and reports in these tests.
private nonisolated struct NoPurchasing: MidgarCreditsPurchasing {
    func products() async throws -> [StoreProduct] { [] }
    func purchaseReceipt(_ productID: String) async throws -> MidgarReceiptResult { .cancelled }
    func events() async -> AsyncStream<MidgarStoreEvent> { AsyncStream { _ in } }
}
