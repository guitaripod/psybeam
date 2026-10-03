import Testing
@testable import PsybeamKit

@Suite("Session notice is shown only when the user needs it")
struct SessionNoticeTests {
    @Test("Offline wins over any balance")
    func offlineWins() {
        #expect(SessionNotice.evaluate(isOnline: false, balance: 0, lowThreshold: 5) == .offline)
        #expect(SessionNotice.evaluate(isOnline: false, balance: 40, lowThreshold: 5) == .offline)
        #expect(SessionNotice.evaluate(isOnline: false, balance: nil, lowThreshold: 5) == .offline)
    }

    @Test("An unread balance never claims the user is out")
    func unknownBalance() {
        #expect(SessionNotice.evaluate(isOnline: true, balance: nil, lowThreshold: 5) == nil)
    }

    @Test("Zero or negative is out of minutes")
    func outOfMinutes() {
        #expect(SessionNotice.evaluate(isOnline: true, balance: 0, lowThreshold: 5) == .outOfMinutes)
        #expect(SessionNotice.evaluate(isOnline: true, balance: -1, lowThreshold: 5) == .outOfMinutes)
    }

    @Test("Below the threshold is low, at it is quiet")
    func lowBoundary() {
        #expect(SessionNotice.evaluate(isOnline: true, balance: 1, lowThreshold: 5) == .lowMinutes(1))
        #expect(SessionNotice.evaluate(isOnline: true, balance: 4, lowThreshold: 5) == .lowMinutes(4))
        #expect(SessionNotice.evaluate(isOnline: true, balance: 5, lowThreshold: 5) == nil)
        #expect(SessionNotice.evaluate(isOnline: true, balance: 120, lowThreshold: 5) == nil)
    }

    @Test("Only the minutes states open the store")
    func storePath() {
        #expect(!SessionNotice.offline.offersStore)
        #expect(SessionNotice.outOfMinutes.offersStore)
        #expect(SessionNotice.lowMinutes(2).offersStore)
    }
}
