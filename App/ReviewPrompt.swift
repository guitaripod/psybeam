import MidgarCommerce
import MidgarCore
import StoreKit
import UIKit

/// Asks for an App Store rating once the user has had a real conversation through Psybeam. `MidgarReviewPolicy`
/// decides whether an ask is due (the shared Midgar rules: not in the first days or sessions, not within 120 days of
/// the last ask or on the version that asked, not within a week of a failed purchase); this type reports each
/// completed translation turn to it and, when it says yes, asks StoreKit once the turn's own success UI has landed
/// and only while nothing else is covering the screen.
///
/// A turn only counts when a leg produced final, non-empty text, so a failed or silent hold never advances it. The
/// prompt never fires before the second such turn: by then the app has done its job twice.
@MainActor
enum ReviewPrompt {
    nonisolated static let firstAskThreshold = 2
    private static let delayAfterSuccess: Duration = .milliseconds(1500)

    /// Guards against a second success landing while the first ask is still delayed: without it, two turns
    /// finishing within the same 1.5s window could each see themselves as due and both call StoreKit.
    private static var askPending = false

    nonisolated static let policy: MidgarReviewPolicy = {
        let storage = MidgarReviewFileStorage(appID: PsybeamMidgar.appID)
        LegacyReviewState.migrate(from: .standard, into: storage)
        return MidgarReviewPolicy(storage: storage)
    }()

    /// Counts one session. Call it once per launch.
    static func beginSession() {
        policy.beginSession()
    }

    /// Reports a purchase that failed, which holds the prompt back for a week.
    nonisolated static func notePurchaseFailure() {
        policy.notePurchaseFailure()
    }

    /// Call when a translation turn finishes with text.
    static func recordSuccess(in scene: UIWindowScene?) {
        let successCount = AppSettings.completedTurns + 1
        AppSettings.completedTurns = successCount

        let due = policy.noteSuccess()
        guard due, successCount >= firstAskThreshold else {
            MidgarLog.info("review prompt skipped at \(successCount) successes: due \(due)", category: .review)
            return
        }
        guard let scene else {
            MidgarLog.info("review prompt skipped: no window scene", category: .review)
            return
        }
        guard !askPending else {
            MidgarLog.info("review prompt skipped: an ask is already pending", category: .review)
            return
        }
        askPending = true

        Task {
            defer { askPending = false }
            try? await Task.sleep(for: delayAfterSuccess)
            ask(in: scene)
        }
    }

    private static func ask(in scene: UIWindowScene) {
        guard scene.activationState == .foregroundActive else {
            MidgarLog.info("review prompt skipped: scene not foreground-active", category: .review)
            return
        }
        guard scene.keyWindow?.rootViewController?.presentedViewController == nil else {
            MidgarLog.info("review prompt skipped: another screen is presented", category: .review)
            return
        }
        policy.notePrompted()
        MidgarLog.info("review prompt requested", category: .review)
        AppStore.requestReview(in: scene)
    }
}
