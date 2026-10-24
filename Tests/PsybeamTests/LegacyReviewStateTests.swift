import Foundation
import MidgarCommerce
import Testing
@testable import Psybeam

struct LegacyReviewStateTests {

    /// Holds one review state in memory. Reads and writes happen under one lock.
    private final class MemoryStorage: MidgarReviewStorage, @unchecked Sendable {
        private let lock = NSLock()
        private var state = MidgarReviewState()

        func load() -> MidgarReviewState {
            lock.lock()
            defer { lock.unlock() }
            return state
        }

        func save(_ state: MidgarReviewState) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            self.state = state
            return true
        }
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "psybeam.tests.review.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func theNewestRecentAskBecomesThePoliciesLastPrompt() {
        let defaults = freshDefaults()
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_750_000_000)
        defaults.set([older.timeIntervalSince1970, newer.timeIntervalSince1970], forKey: LegacyReviewState.askDatesKey)
        let storage = MemoryStorage()

        LegacyReviewState.migrate(from: defaults, into: storage)

        #expect(storage.load().lastPrompt == newer)
        #expect(defaults.object(forKey: LegacyReviewState.askDatesKey) == nil)
    }

    @Test func theOldPerVersionFlagCarriesItsVersionAndIsRetired() {
        let defaults = freshDefaults()
        defaults.set("1.0.1", forKey: LegacyReviewState.legacyPromptedVersionKey)
        let storage = MemoryStorage()
        let now = Date(timeIntervalSince1970: 1_760_000_000)

        LegacyReviewState.migrate(from: defaults, into: storage, now: now)

        #expect(storage.load().lastPrompt == now)
        #expect(storage.load().lastPromptedVersion == "1.0.1")
        #expect(defaults.object(forKey: LegacyReviewState.legacyPromptedVersionKey) == nil)
    }

    @Test func aPersonNeverAskedStaysUnasked() {
        let storage = MemoryStorage()

        LegacyReviewState.migrate(from: freshDefaults(), into: storage)

        #expect(storage.load().lastPrompt == nil)
    }

    @Test func theMigrationRunsOnce() {
        let defaults = freshDefaults()
        let storage = MemoryStorage()
        LegacyReviewState.migrate(from: defaults, into: storage)
        defaults.set([1_700_000_000.0], forKey: LegacyReviewState.askDatesKey)

        LegacyReviewState.migrate(from: defaults, into: storage)

        #expect(storage.load().lastPrompt == nil)
    }

    @Test func aNewerPolicyStateIsNotOverwritten() {
        let defaults = freshDefaults()
        defaults.set([1_700_000_000.0], forKey: LegacyReviewState.askDatesKey)
        let storage = MemoryStorage()
        let existing = Date(timeIntervalSince1970: 1_790_000_000)
        storage.save(MidgarReviewState(lastPrompt: existing))

        LegacyReviewState.migrate(from: defaults, into: storage)

        #expect(storage.load().lastPrompt == existing)
    }

    @Test func theRetiredCountersAreRemoved() {
        let defaults = freshDefaults()
        for key in LegacyReviewState.retiredKeys { defaults.set(3, forKey: key) }

        LegacyReviewState.migrate(from: defaults, into: MemoryStorage())

        for key in LegacyReviewState.retiredKeys { #expect(defaults.object(forKey: key) == nil) }
    }
}
