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

public extension TranslationState {
    /// Maps a realtime-leg failure to the UI state, with a strict honesty rule:
    /// a cause-specific state is returned only when the cause is actually known.
    /// `.network` becomes `.offline` only when `isOnline` is false (the OS
    /// confirmed no path) — otherwise it's a neutral retry, never a guess.
    /// `.cancelled` returns nil (deliberate teardown, nothing to show).
    static func failure(for error: CallError, isOnline: Bool) -> TranslationState? {
        switch error {
        case .quota: .quotaExhausted
        case .permission(let permission): .permissionDenied(permission)
        case .unsupportedLanguage: .error(.unsupportedLanguage)
        case .server(let message): .error(.server(message))
        case .network: isOnline ? .error(.network) : .offline
        case .cancelled: nil
        }
    }
}
