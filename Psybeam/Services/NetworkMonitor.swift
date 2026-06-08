import Foundation
import Network

/// Lightweight reachability so error states stay honest: "No connection" is shown
/// only when the OS actually reports no satisfied path, never guessed from a
/// failure that could have many causes.
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.guitaripod.psybeam.network")
    private let lock = NSLock()
    private var online = true

    var isOnline: Bool {
        lock.lock(); defer { lock.unlock() }
        return online
    }

    private init() {}

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.online = path.status == .satisfied
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }
}
