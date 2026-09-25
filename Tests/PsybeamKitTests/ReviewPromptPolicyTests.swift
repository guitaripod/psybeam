import Foundation
import Testing
@testable import PsybeamKit

@Suite("Review prompt policy")
struct ReviewPromptPolicyTests {
    private let day: TimeInterval = 24 * 60 * 60
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func eligible(
        _ successCount: Int,
        askDates: [Date] = [],
        successCountAtLastAsk: Int = 0,
        now: Date? = nil
    ) -> Bool {
        ReviewPromptPolicy.isEligible(
            successCount: successCount,
            askDates: askDates,
            successCountAtLastAsk: successCountAtLastAsk,
            now: now ?? self.now
        )
    }

    @Test("No ask after only one success")
    func noAskAtOneSuccess() {
        #expect(!eligible(1))
    }

    @Test("The first ask fires the moment the second success lands")
    func asksAtTwoSuccesses() {
        #expect(eligible(2))
    }

    @Test("No re-ask 13 days after the last ask, one day short of the cooldown")
    func noReAskAtThirteenDays() {
        let lastAsk = now.addingTimeInterval(-13 * day)
        #expect(!eligible(10, askDates: [lastAsk], successCountAtLastAsk: 2, now: now))
    }

    @Test("A re-ask is allowed at exactly 14 days, once enough successes have landed")
    func reAskAtExactlyFourteenDays() {
        let lastAsk = now.addingTimeInterval(-14 * day)
        #expect(eligible(5, askDates: [lastAsk], successCountAtLastAsk: 2, now: now))
    }

    @Test("No re-ask on 2 new successes, one short of the required 3")
    func noReAskOnTwoNewSuccesses() {
        let lastAsk = now.addingTimeInterval(-20 * day)
        #expect(!eligible(4, askDates: [lastAsk], successCountAtLastAsk: 2, now: now))
    }

    @Test("A re-ask is allowed on exactly 3 new successes, once the cooldown has passed")
    func reAskOnExactlyThreeNewSuccesses() {
        let lastAsk = now.addingTimeInterval(-20 * day)
        #expect(eligible(5, askDates: [lastAsk], successCountAtLastAsk: 2, now: now))
    }

    @Test("A re-ask fires once both the cooldown and the new successes are satisfied")
    func reAsksAfterBothConditions() {
        let lastAsk = now.addingTimeInterval(-15 * day)
        #expect(eligible(5, askDates: [lastAsk], successCountAtLastAsk: 2, now: now))
    }

    @Test("A fourth ask never fires within a rolling year of three prior asks")
    func neverAFourthAskWithinTheYear() {
        let askDates = [
            now.addingTimeInterval(-300 * day),
            now.addingTimeInterval(-200 * day),
            now.addingTimeInterval(-15 * day),
        ]
        #expect(!eligible(100, askDates: askDates, successCountAtLastAsk: 2, now: now))
    }

    @Test("A fourth ask is allowed once the oldest of three asks ages out of the year")
    func fourthAskAllowedOnceOldestAgesOut() {
        let askDates = [
            now.addingTimeInterval(-366 * day),
            now.addingTimeInterval(-200 * day),
            now.addingTimeInterval(-15 * day),
        ]
        #expect(eligible(100, askDates: askDates, successCountAtLastAsk: 40, now: now))
    }
}
