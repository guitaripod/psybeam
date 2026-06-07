/// The canonical UI state machine. Every case must be visually legible to a
/// clueless local without reading a word — the side-color contract is the only
/// thing the stranger has to learn. The associated values drive presentation
/// (mic level animates the seam, `isReplay` distinguishes a re-spoken turn,
/// `passthrough` shows the "same language" glyph instead of hanging).
public enum TranslationState: Sendable, Equatable {
    case idle
    case armed(turn: Side)
    case listening(turn: Side, level: Float)
    case processing(from: Side)
    case speaking(to: Side, isReplay: Bool)
    case passthrough(side: Side)
    case reconnecting
    case quotaExhausted
    case permissionDenied(Permission)
    case offline
    case error(TranslationError)
}
