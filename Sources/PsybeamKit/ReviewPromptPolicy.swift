import Foundation

/// Whether the moment is right to ask for an App Store rating.
///
/// A success is a translation turn that actually landed: you spoke, they heard it
/// in their language. The first ask fires the moment the second one lands — early,
/// because by then the app has already done its job twice. "Not Now" and a silent
/// dismissal look the same to the app, so a later ask only comes back once both two
/// weeks and three more successes have passed since the last one, and it never
/// crosses Apple's own cap of three asks in a rolling year.
public enum ReviewPromptPolicy {
    public static let firstAskThreshold = 2
    public static let successesBetweenAsks = 3
    public static let cooldown: TimeInterval = 14 * 24 * 60 * 60
    public static let capWindow: TimeInterval = 365 * 24 * 60 * 60
    public static let maxAsksPerWindow = 3

    /// `askDates` holds every prior ask in any order; only the ones still inside
    /// the rolling year count toward the cap, but the most recent one always
    /// governs the cooldown and the new-successes count, even once older asks
    /// age out.
    public static func isEligible(
        successCount: Int,
        askDates: [Date],
        successCountAtLastAsk: Int,
        now: Date
    ) -> Bool {
        guard successCount >= firstAskThreshold else { return false }
        let asksInWindow = askDates.filter { now.timeIntervalSince($0) < capWindow }
        guard asksInWindow.count < maxAsksPerWindow else { return false }
        guard let lastAsk = askDates.max() else { return true }
        guard now.timeIntervalSince(lastAsk) >= cooldown else { return false }
        return successCount - successCountAtLastAsk >= successesBetweenAsks
    }
}
