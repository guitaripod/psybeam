import Combine
import Foundation

/// Collects a publisher's values and polls until a predicate holds (or times out)
/// — the leg publishes asynchronously off its internal Tasks, so tests await an
/// outcome rather than a fixed delay.
@MainActor
final class Recorder<Value> {
    private var values: [Value] = []
    private var cancellable: AnyCancellable?

    init(_ publisher: some Publisher<Value, Never>) {
        cancellable = publisher.sink { [weak self] value in self?.values.append(value) }
    }

    func waitFor(timeout: Duration = .seconds(2), _ predicate: @escaping (Value) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        repeat {
            if values.contains(where: predicate) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        return values.contains(where: predicate)
    }
}

@MainActor
final class SignalRecorder {
    private var count = 0
    private var cancellable: AnyCancellable?

    init(_ publisher: some Publisher<Void, Never>) {
        cancellable = publisher.sink { [weak self] in self?.count += 1 }
    }

    func waitForSignal(timeout: Duration = .seconds(2)) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        repeat {
            if count > 0 { return true }
            try? await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        return count > 0
    }
}

@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ predicate: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    repeat {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    } while ContinuousClock.now < deadline
    return predicate()
}
