import UIKit

extension SettingsViewController {
    /// Deletes the account on the server, then the local records, and tells the person. A failure reaches the settings
    /// list, which shows it in its own alert; nothing local is touched until the server has answered.
    func deleteAccount() async throws {
        do {
            try await AccountService().deleteAccount()
        } catch {
            throw AccountDeletionFailure()
        }
        wipeLocalData()
        viewModel.end()
        await AICreditsManager.store.bootstrap()
        showAccountDeleted()
    }

    private func wipeLocalData() {
        AppSettings.aiConsentGranted = false
        AppSettings.pendingSessionId = nil
        AppSettings.pendingReservedMinutes = 0
        try? DatabaseManager.shared.wipe()
        PsybeamMidgar.eraseLogFiles()
    }

    private func showAccountDeleted() {
        let alert = UIAlertController(
            title: String(localized: "Account Deleted"),
            message: String(localized: "Your account and data have been removed."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { [weak self] _ in
            self?.dismiss(animated: true) { self?.onDismiss?() }
        })
        present(alert, animated: true)
    }

    private struct AccountDeletionFailure: LocalizedError {
        var errorDescription: String? { String(localized: "Please check your connection and try again.") }
    }
}
