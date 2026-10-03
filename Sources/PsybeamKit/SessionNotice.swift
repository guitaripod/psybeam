/// What the screen should say before the user presses anything, so the two
/// ways a hold can never succeed are known up front instead of after the hold.
///
/// Offline outranks the balance: with no connection neither the balance nor a
/// purchase can be reached. A balance that has not been read yet says nothing,
/// so a slow launch never claims the user is out of minutes.
public enum SessionNotice: Sendable, Equatable {
    case offline
    case outOfMinutes
    case lowMinutes(Int)

    public static func evaluate(isOnline: Bool, balance: Int?, lowThreshold: Int) -> SessionNotice? {
        guard isOnline else { return .offline }
        guard let balance else { return nil }
        if balance <= 0 { return .outOfMinutes }
        return balance < lowThreshold ? .lowMinutes(balance) : nil
    }

    /// Whether tapping the notice should open the store.
    public var offersStore: Bool {
        switch self {
        case .offline: false
        case .outOfMinutes, .lowMinutes: true
        }
    }
}
