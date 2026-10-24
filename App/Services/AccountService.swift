import Foundation
import AICreditsCore
import MidgarCore
import MidgarCredits

/// Server-side account deletion for App Store 5.1.1(v). The shipped app's only account is the mako identity behind the
/// api key (anonymous by default, optionally linked to Sign in with Apple), which the Midgar ID's wallet is linked to.
/// `deleteAccount()` removes that account and its credit ledger on the server through
/// `MidgarCredits.deleteLegacyAccount()`, which also erases this app's partition of the wallet, then clears the local
/// identity so the next bootstrap mints a fresh anonymous account. Without the wallet (a host that reaches no Midgar
/// service) AICredits deletes its own identity. The Midgar ID is shared with the other Midgar apps and stays. A failure
/// leaves the local identity in place, so the person can retry.
final class AccountService: Sendable {
    private let client: AICreditsClient
    private let credits: MidgarCredits?

    init(
        client: AICreditsClient = AICreditsManager.shared.client,
        credits: MidgarCredits? = PsybeamMidgar.shared.credits
    ) {
        self.client = client
        self.credits = credits
    }

    func deleteAccount() async throws {
        do {
            try await deleteLegacyAccount()
        } catch {
            MidgarLog.error("account delete failed", category: .auth)
            throw AccountError.server
        }
        await client.signOut()
        MidgarLog.info("account deleted", category: .auth)
    }

    private func deleteLegacyAccount() async throws {
        guard let credits else {
            try await client.deleteIdentity()
            return
        }
        try await credits.deleteLegacyAccount()
    }

    enum AccountError: Error { case server }
}
