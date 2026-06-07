/// Failure modes for the WebRTC realtime call leg.
public enum CallError: Sendable, Equatable, Error {
    case network
    case quota
    case permission(Permission)
    case unsupportedLanguage
    case server(String)
    case cancelled
}

/// Failure modes for the translation pipeline surfaced to the UI state machine.
public enum TranslationError: Sendable, Equatable, Error {
    case network
    case quota
    case permission(Permission)
    case unsupportedLanguage
    case server(String)
    case cancelled
}
