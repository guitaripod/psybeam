import Foundation
import PsybeamKit

/// Raw values align with `UIUserInterfaceStyle` (unspecified/light/dark) so a
/// stored mode maps straight onto a window override.
enum AppearanceMode: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2
}

enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    private enum Key {
        static let travelerLanguage = "psybeam.travelerLanguage"
        static let localLanguage = "psybeam.localLanguage"
        static let autoDetectLocation = "psybeam.autoDetectLocation"
        static let keepScreenBright = "psybeam.keepScreenBright"
        static let turnChime = "psybeam.turnChime"
        static let appearance = "psybeam.appearance"
        static let aiConsentGranted = "psybeam.aiConsentGranted"
        static let pendingSessionId = "psybeam.pendingSessionId"
        static let pendingReservedMinutes = "psybeam.pendingReservedMinutes"
        static let completedTurns = "psybeam.completedTurns"
        static let reviewAskDates = "psybeam.reviewAskDates"
        static let reviewSuccessCountAtLastAsk = "psybeam.reviewSuccessCountAtLastAsk"
        static let reviewPromptMigrated = "psybeam.reviewPromptMigrated"
        static let firstRunStage = "psybeam.firstRunStage"
    }

    /// Pre-1.1.2 legacy key: asked at most once per app version, with no date
    /// recorded.
    private static let legacyRatingPromptShownVersionKey = "psybeam.ratingPromptShownVersion"

    /// Progress through the destination picker and the try-it-yourself coach.
    /// Unset on a fresh install and on updates from before the walkthrough.
    static var firstRunStage: FirstRunStage {
        get { FirstRunStage.resolve(stored: defaults.string(forKey: Key.firstRunStage), completedTurns: completedTurns) }
        set { defaults.set(newValue.rawValue, forKey: Key.firstRunStage) }
    }

    /// Translation turns that actually produced text. Gates the rating prompt.
    static var completedTurns: Int {
        get { defaults.integer(forKey: Key.completedTurns) }
        set { defaults.set(newValue, forKey: Key.completedTurns) }
    }

    /// Every prior review-prompt ask, for the 14-day cooldown and Apple's
    /// three-per-year cap.
    static var reviewAskDates: [Date] {
        get { (defaults.array(forKey: Key.reviewAskDates) as? [Double] ?? []).map(Date.init(timeIntervalSince1970:)) }
        set { defaults.set(newValue.map(\.timeIntervalSince1970), forKey: Key.reviewAskDates) }
    }

    /// `completedTurns` at the moment of the most recent ask, so the policy
    /// can tell how many successes are new since then.
    static var reviewSuccessCountAtLastAsk: Int {
        get { defaults.integer(forKey: Key.reviewSuccessCountAtLastAsk) }
        set { defaults.set(newValue, forKey: Key.reviewSuccessCountAtLastAsk) }
    }

    /// One-time move off the pre-1.1.2 "once per app version" flag. The exact
    /// date of a prior ask was never recorded, so a migrated ask is stamped as
    /// happening now: that starts its 14-day cooldown fresh and still spends
    /// one of the three yearly asks, so a migrated install can never end up
    /// asking more often than the cap allows.
    static func migrateLegacyReviewPromptStateIfNeeded() {
        guard defaults.object(forKey: Key.reviewPromptMigrated) == nil else { return }
        defaults.set(true, forKey: Key.reviewPromptMigrated)
        defer { defaults.removeObject(forKey: legacyRatingPromptShownVersionKey) }
        guard defaults.string(forKey: legacyRatingPromptShownVersionKey) != nil else { return }
        reviewAskDates = [Date()]
        reviewSuccessCountAtLastAsk = completedTurns
    }

    /// A reserved realtime session that may not have been settled (e.g. the app
    /// was killed mid-call). Settled on next launch so the unused reservation is
    /// refunded. Cleared on a successful settle.
    static var pendingSessionId: String? {
        get { defaults.string(forKey: Key.pendingSessionId) }
        set { defaults.set(newValue, forKey: Key.pendingSessionId) }
    }

    static var pendingReservedMinutes: Int {
        get { defaults.integer(forKey: Key.pendingReservedMinutes) }
        set { defaults.set(newValue, forKey: Key.pendingReservedMinutes) }
    }

    static var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: defaults.integer(forKey: Key.appearance)) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    /// Pre-audio consent to cloud third-party-AI translation (App Review 5.1.2(i)).
    /// Defaults to false — no audio reaches OpenAI until this is granted.
    static var aiConsentGranted: Bool {
        get { defaults.bool(forKey: Key.aiConsentGranted) }
        set { defaults.set(newValue, forKey: Key.aiConsentGranted) }
    }

    static var travelerLanguage: String {
        get { defaults.string(forKey: Key.travelerLanguage) ?? (Locale.current.language.languageCode?.identifier ?? "en") }
        set { defaults.set(newValue, forKey: Key.travelerLanguage) }
    }

    /// Never the traveler's own language: a missing or colliding value, such as
    /// the en↔en pair an at-home GPS fix stored before 1.1.1, reads as the
    /// default destination for the traveler's language.
    static var localLanguage: String {
        get { LanguagePair.local(stored: defaults.string(forKey: Key.localLanguage), traveler: travelerLanguage) }
        set { defaults.set(newValue, forKey: Key.localLanguage) }
    }

    static var autoDetectLocation: Bool {
        get { (defaults.object(forKey: Key.autoDetectLocation) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Key.autoDetectLocation) }
    }

    static var keepScreenBright: Bool {
        get { (defaults.object(forKey: Key.keepScreenBright) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Key.keepScreenBright) }
    }

    static var turnChime: Bool {
        get { (defaults.object(forKey: Key.turnChime) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Key.turnChime) }
    }
}
