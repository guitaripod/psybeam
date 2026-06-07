public enum Side: String, Sendable, Codable, CaseIterable {
    case traveler
    case local
}

public extension Side {
    var other: Side {
        switch self {
        case .traveler: .local
        case .local: .traveler
        }
    }
}
