import Foundation
import MidgarCommerce

/// The ask history the app kept before `MidgarReviewPolicy`: a list of ask dates, and before that a flag with the app
/// version that had asked. A person who was asked recently must not be asked again the day the policy changes, so
/// the newest ask becomes the policy's last prompt the first time it runs.
nonisolated enum LegacyReviewState {
    static let askDatesKey = "psybeam.reviewAskDates"
    static let legacyPromptedVersionKey = "psybeam.ratingPromptShownVersion"
    static let retiredKeys = ["psybeam.reviewSuccessCountAtLastAsk", "psybeam.reviewPromptMigrated"]
    static let migratedKey = "psybeam.review.migratedToMidgar"

    static func migrate(from defaults: UserDefaults, into storage: any MidgarReviewStorage, now: Date = Date()) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        let promptedVersion = defaults.string(forKey: legacyPromptedVersionKey)
        let lastAsk = lastAsk(in: defaults, promptedVersion: promptedVersion, now: now)
        retire(in: defaults)
        guard let lastAsk else { return }
        var state = storage.load()
        guard state.lastPrompt == nil else { return }
        state.lastPrompt = lastAsk
        state.lastPromptedVersion = promptedVersion
        storage.save(state)
    }

    /// The newest recorded ask, or `now` when only the old per-version flag survives, since its date was never kept.
    private static func lastAsk(in defaults: UserDefaults, promptedVersion: String?, now: Date) -> Date? {
        let seconds = defaults.array(forKey: askDatesKey) as? [TimeInterval] ?? []
        if let newest = seconds.max() { return Date(timeIntervalSince1970: newest) }
        return promptedVersion == nil ? nil : now
    }

    /// Removes the values only the retired mechanism read, once the policy holds what they said.
    private static func retire(in defaults: UserDefaults) {
        defaults.removeObject(forKey: askDatesKey)
        defaults.removeObject(forKey: legacyPromptedVersionKey)
        for key in retiredKeys { defaults.removeObject(forKey: key) }
    }
}
