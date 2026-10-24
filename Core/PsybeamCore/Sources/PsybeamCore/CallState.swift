/// The lifecycle of the direct WebRTC leg to the realtime model. `live(turn:)`
/// names the single active direction — bidirectional translation is turn-gated,
/// never two hot sessions. `reconnecting` covers ICE restart, `ek_` expiry
/// mid-handshake, and the 60-minute hard cap re-mint; it is routine, not an
/// alarm.
public enum CallState: Sendable, Equatable {
    case idle
    case connecting
    case live(turn: Side)
    case reconnecting
    case interrupted
    case ended
    case failed(CallError)
}
