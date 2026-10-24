import Combine
import Foundation
import MidgarCore
import MidgarCredits
import MidgarCreditsUI
import Observation

/// The balance of the wallet for the screens: Settings shows it, the conversation decides from it whether to tell the
/// person they are running low, and the credit store sheet is built on its source. It is read at launch, when the app
/// comes to the foreground, after a realtime session settles and after a purchase, and it follows what
/// ``MidgarCredits/events()`` reports, so a purchase made in the store sheet reaches every screen without anyone
/// telling them. UIKit screens bind to ``balanceChanges``, which sends only when the balance actually changed.
///
/// The source is nil where the app reaches no Midgar service (a test host), and the balance then stays 0.
@MainActor @Observable
final class CreditsModel {
    /// A balance below this tells the person they are running low.
    nonisolated static let lowBalanceThreshold = 5

    @ObservationIgnored let source: (any MidgarCreditStoreSource)?
    @ObservationIgnored let balanceChanges = PassthroughSubject<Int, Never>()
    @ObservationIgnored private var reading: Task<Int?, Never>?

    private(set) var balance = 0

    init(source: (any MidgarCreditStoreSource)?) {
        self.source = source
    }

    /// The model of the running app: the Midgar wallet, a fixed demo wallet in a DEBUG demo capture, or no wallet in a
    /// test host.
    static func live() -> CreditsModel {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PSYBEAM_DEMO"] != nil {
            return CreditsModel(source: DemoCreditsSource())
        }
        #endif
        guard let wallet = PsybeamMidgar.shared.credits else {
            return CreditsModel(source: nil)
        }
        return CreditsModel(
            source: ObservedCreditsSource(wallet: wallet, purchaseFailed: ObservedCreditsSource.recordPurchaseFailure))
    }

    /// Reads the balance, then follows the wallet's events until the stream ends. Run it for the life of the app.
    func start() async {
        await refresh()
        await observe()
    }

    /// Drops the balance of an account that was deleted, so no screen shows credits the wallet no longer holds.
    func forget() {
        apply(0)
    }

    /// Reads the balance from the wallet and returns it, or nil when there is no wallet or the read failed, which keeps
    /// the last balance known. A read that is already running is joined instead of repeated.
    @discardableResult
    func refresh() async -> Int? {
        if let reading {
            return await reading.value
        }
        guard source != nil else {
            return nil
        }
        let task = Task { await read() }
        reading = task
        let balance = await task.value
        reading = nil
        return balance
    }

    func handle(_ event: MidgarCreditsEvent) async {
        switch event {
        case .balanceChanged(let changed):
            apply(changed.credits)
        case .purchaseCredited:
            if let known = await source?.balance {
                apply(known.credits)
            }
        }
    }

    private func read() async -> Int? {
        do {
            guard let read = try await source?.refresh() else {
                return nil
            }
            apply(read.credits)
            return read.credits
        } catch {
            MidgarLog.notice("credits balance read failed: \(error)", category: .auth)
            return nil
        }
    }

    private func observe() async {
        guard let source else {
            return
        }
        for await event in await source.events() {
            await handle(event)
        }
    }

    private func apply(_ credits: Int) {
        guard credits != balance else {
            return
        }
        balance = credits
        balanceChanges.send(credits)
    }
}
