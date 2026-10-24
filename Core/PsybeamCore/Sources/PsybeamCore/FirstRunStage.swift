/// Where a new user is in the first-run walkthrough: pick a destination, then
/// try one turn in each direction with the matching button beckoning.
///
/// Most first launches happen at home, before the trip, where a GPS-seeded pair
/// would have nothing to translate into. The walkthrough gives that user a real
/// destination language and has them hear their own voice come back in it.
public enum FirstRunStage: String, Sendable, CaseIterable {
    case chooseDestination
    case holdYours
    case holdTheirs
    case done

    /// A stored stage wins. With none stored, anyone who already finished a
    /// translation, such as a user updating from before the walkthrough
    /// existed, skips it entirely.
    public static func resolve(stored: String?, completedTurns: Int) -> FirstRunStage {
        if let stored, let stage = FirstRunStage(rawValue: stored) { return stage }
        return completedTurns > 0 ? .done : .chooseDestination
    }

    /// Whether the destination picker is still owed.
    public var offersDestination: Bool { self == .chooseDestination }

    /// Picking a destination and skipping the picker both lead to the coach,
    /// which works with whatever pair is set.
    public var afterDestination: FirstRunStage {
        self == .chooseDestination ? .holdYours : self
    }

    /// Your first finished turn invites the reply; the reply ends the walkthrough.
    public func after(turnBy speaker: Side) -> FirstRunStage {
        switch (self, speaker) {
        case (.holdYours, .traveler): .holdTheirs
        case (.holdTheirs, .local): .done
        default: self
        }
    }

    /// The button the coach points at, if the walkthrough is on a coaching step.
    public var beckoning: Side? {
        switch self {
        case .holdYours: .traveler
        case .holdTheirs: .local
        case .chooseDestination, .done: nil
        }
    }
}
