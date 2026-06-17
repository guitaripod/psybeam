import Foundation
import AICreditsCore

/// Server-side account deletion for App Store 5.1.1(v). The shipped app's only
/// account is the mako identity the AICredits wallet is keyed to (anonymous by
/// default, optionally linked to Sign in with Apple). `deleteAccount()` removes
/// that identity and its credit ledger on the server, then clears the local
/// identity so the next bootstrap mints a fresh anonymous wallet.
final class AccountService: Sendable {
    private let client: AICreditsClient
    private let baseURL: URL
    private let appID = "psybeam"

    init(
        client: AICreditsClient = AICreditsManager.shared.client,
        baseURL: URL = AICreditsManager.shared.baseURL
    ) {
        self.client = client
        self.baseURL = baseURL
    }

    func deleteAccount() async throws {
        let apiKey = try await client.bootstrap().apiKey
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/identity"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(appID, forHTTPHeaderField: "X-App-ID")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            AppLogger.shared.error("account delete failed", category: .auth)
            throw AccountError.server
        }
        await client.signOut()
        AppLogger.shared.info("account deleted", category: .auth)
    }

    enum AccountError: Error { case server }
}
