import PsybeamKit
import StoreKit
import UIKit

/// Asks for an App Store rating once the user has had a real conversation through
/// Psybeam, and again later if that didn't lead anywhere — never more than the
/// three tries a year Apple allows.
///
/// Rating count is both an App Store ranking input and the strongest conversion
/// signal on a product page. The gate is completed translation *turns* — a turn
/// only counts when a leg produced final, non-empty text, so a failed or silent
/// hold never advances it. `ReviewPromptPolicy` in PsybeamKit owns the eligibility
/// math as a pure function of the stored counts and dates; this type owns the
/// storage and picks the moment, delayed slightly so the turn's own success UI
/// lands first, and only while nothing else is covering the screen.
@MainActor
enum ReviewPrompt {
    private static let delayAfterSuccess: Duration = .milliseconds(1500)

    /// Guards against a second success landing while the first ask is still
    /// delayed: without it, two turns finishing within the same 1.5s window
    /// could each see themselves as eligible and both call StoreKit.
    private static var askPending = false

    /// Call when a translation turn finishes with text.
    static func recordSuccess(in scene: UIWindowScene?) {
        let successCount = AppSettings.completedTurns + 1
        AppSettings.completedTurns = successCount

        guard ReviewPromptPolicy.isEligible(
            successCount: successCount,
            askDates: AppSettings.reviewAskDates,
            successCountAtLastAsk: AppSettings.reviewSuccessCountAtLastAsk,
            now: Date()
        ) else {
            AppLogger.shared.info("review prompt skipped at \(successCount) successes", category: .app)
            return
        }
        guard let scene else {
            AppLogger.shared.info("review prompt skipped: no window scene", category: .app)
            return
        }
        guard !askPending else {
            AppLogger.shared.info("review prompt skipped: an ask is already pending", category: .app)
            return
        }
        askPending = true

        Task {
            defer { askPending = false }
            try? await Task.sleep(for: delayAfterSuccess)
            ask(in: scene, successCount: successCount)
        }
    }

    private static func ask(in scene: UIWindowScene, successCount: Int) {
        guard scene.activationState == .foregroundActive else {
            AppLogger.shared.info("review prompt skipped: scene not foreground-active", category: .app)
            return
        }
        guard scene.keyWindow?.rootViewController?.presentedViewController == nil else {
            AppLogger.shared.info("review prompt skipped: another screen is presented", category: .app)
            return
        }

        var askDates = AppSettings.reviewAskDates
        askDates.append(Date())
        AppSettings.reviewAskDates = askDates
        AppSettings.reviewSuccessCountAtLastAsk = successCount
        AppLogger.shared.info("review prompt requested (#\(askDates.count)) after \(successCount) successes", category: .app)
        AppStore.requestReview(in: scene)
    }
}
