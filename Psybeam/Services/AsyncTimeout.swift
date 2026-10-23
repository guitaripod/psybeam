import Foundation

/// Bounds an async call that may never return, so a slow Midgar identity service cannot hold up the call it only
/// decorates. A task group cannot help there: it waits for every child, including a hung one, before it returns.
nonisolated enum AsyncTimeout {

    struct Expired: Error {}

    static func run<T: Sendable>(
        seconds: Double,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = ResumeGate()
        return try await withCheckedThrowingContinuation { continuation in
            let work = Task {
                do {
                    let value = try await operation()
                    if gate.claim() { continuation.resume(returning: value) }
                } catch {
                    if gate.claim() { continuation.resume(throwing: error) }
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if gate.claim() {
                    work.cancel()
                    continuation.resume(throwing: Expired())
                }
            }
        }
    }

    /// Lets exactly one of the racing tasks resume the continuation. Safe to share because `claim` reads and writes
    /// its flag under one lock.
    private final class ResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
