import Foundation
import AICreditsCore
import MidgarCore

/// Server-side account deletion for App Store 5.1.1(v). The shipped app's only
/// account is the mako identity the AICredits wallet is keyed to (anonymous by
/// default, optionally linked to Sign in with Apple). `deleteAccount()` removes
/// that identity and its credit ledger on the server, then clears the local
/// identity so the next bootstrap mints a fresh anonymous wallet. The Midgar ID
/// is shared with the other Midgar apps and stays.
final class AccountService: Sendable {
    private let client: AICreditsClient
    private let gateway: MakoGateway

    init(
        client: AICreditsClient = AICreditsManager.shared.client,
        gateway: MakoGateway = PsybeamMidgar.shared.mako
    ) {
        self.client = client
        self.gateway = gateway
    }

    func deleteAccount() async throws {
        let apiKey = try await client.bootstrap().apiKey
        do throws(MidgarHTTPError) {
            _ = try await gateway.send(.delete, path: "v1/identity", apiKey: apiKey)
        } catch {
            MidgarLog.error("account delete failed", category: .auth)
            throw AccountError.server
        }
        await client.signOut()
        MidgarLog.info("account deleted", category: .auth)
    }

    enum AccountError: Error { case server }
}
