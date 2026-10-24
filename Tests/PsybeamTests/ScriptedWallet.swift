import Foundation
import MidgarCredits
import MidgarCreditsUI

/// A wallet the test controls: what a read answers, how many reads there were, and the stream of events the model follows.
actor ScriptedWallet: MidgarCreditStoreSource {
    struct Offline: Error {}

    private var credits: Int
    private var fails = false
    private(set) var reads = 0
    private let stream: AsyncStream<MidgarCreditsEvent>
    private let continuation: AsyncStream<MidgarCreditsEvent>.Continuation

    init(credits: Int) {
        self.credits = credits
        (stream, continuation) = AsyncStream.makeStream()
    }

    var balance: MidgarCreditsBalance? { balanceValue }

    var unconfirmedPurchases: Int { 0 }

    func set(credits: Int, failing: Bool = false) {
        self.credits = credits
        fails = failing
    }

    func emit(_ event: MidgarCreditsEvent) {
        continuation.yield(event)
    }

    func refresh() async throws -> MidgarCreditsBalance {
        reads += 1
        try? await Task.sleep(for: .milliseconds(20))
        if fails {
            throw Offline()
        }
        return balanceValue
    }

    func offers() async throws -> [MidgarCreditsOffer] { [] }

    func buy(_ packID: String) async throws -> MidgarCreditsPurchaseResult { .cancelled }

    func events() async -> AsyncStream<MidgarCreditsEvent> { stream }

    private var balanceValue: MidgarCreditsBalance {
        MidgarCreditsBalance(credits: credits, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
}

/// Polls until a condition holds or the timeout passes, for outcomes that arrive from other tasks.
@MainActor
func eventually(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return await condition()
}
