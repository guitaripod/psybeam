import StoreKit
import UIKit

/// Asks for an App Store rating once the user has had a real conversation through Psybeam, and at
/// most once per app version.
///
/// Rating count is both an App Store ranking input and the strongest conversion signal on a
/// product page, and Psybeam shipped with no way to ask for one. The gate is completed translation
/// *turns* — a turn only counts when a leg produced final, non-empty text, so a failed or silent
/// hold never advances it. Six turns is roughly three back-and-forth exchanges: enough that the
/// user has seen the app do its job, not so many that only power users are ever asked.
@MainActor
enum ReviewPrompt {
    private static let turnsBeforeAsking = 6

    /// Call when a translation turn finishes with text.
    static func recordCompletedTurn(in scene: UIWindowScene?) {
        let turns = AppSettings.completedTurns + 1
        AppSettings.completedTurns = turns

        guard turns >= turnsBeforeAsking else { return }
        guard AppSettings.ratingPromptShownVersion != currentVersion, let scene else { return }
        AppSettings.ratingPromptShownVersion = currentVersion
        AppLogger.shared.info("review prompt requested after \(turns) turns", category: .app)
        AppStore.requestReview(in: scene)
    }

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
