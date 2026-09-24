import StoreKit
import UIKit

/// Asks for an App Store rating once the user has had a real conversation through Psybeam, and at
/// most once per app version.
///
/// Rating count is both an App Store ranking input and the strongest conversion signal on a
/// product page, and Psybeam shipped with no way to ask for one. The gate is completed translation
/// *turns* — a turn only counts when a leg produced final, non-empty text, so a failed or silent
/// hold never advances it. Two turns is one full exchange, you spoke and they answered: the
/// moment the app has visibly done its job. Asking later meant almost nobody was ever asked, and
/// the system already caps how often the prompt can appear.
@MainActor
enum ReviewPrompt {
    private static let turnsBeforeAsking = 2

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
