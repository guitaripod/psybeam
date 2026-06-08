/// The WebRTC call leg, implemented app-side by an actor owning
/// `RTCPeerConnection` + `RTCAudioSession`. The core exposes only `AsyncStream`
/// — no Combine — so the surface is identical on macOS and Linux.
public protocol RealtimeCallProviding: Sendable {
    var states: AsyncStream<CallState> { get }
    var transcripts: AsyncStream<TranscriptDelta> { get }
    var levels: AsyncStream<Float> { get }
    func connect(spec: TranslationSessionSpec) async throws
    func setMicActive(_ active: Bool) async
    func setTurn(_ side: Side) async
    func bargeIn() async
    func hangUp() async
}

/// Brokers a gated ephemeral-token mint through the Worker (the real key never
/// leaves Cloudflare). The app implementation performs the authenticated HTTPS
/// round-trip and returns the `ek_` plus the SDP URL for the direct exchange.
public protocol TranslationProviding: Sendable {
    func requestSession(pair: LanguagePair, direction: Side) async throws -> SessionToken
    func reportUsage(sessionId: String, minutesUsed: Int) async
}

/// GPS-driven local-language suggestions. The pure resolution logic takes a
/// country code (online MVP path) and a device locale; CoreLocation lives only
/// in the app's actor implementation.
public protocol LocationLanguageProviding: Sendable {
    var suggestions: AsyncStream<LanguageSuggestion> { get }
    func refreshOnForeground() async
    func resolve(countryCode: String, deviceLocale: String) -> LanguageSuggestion
}

/// The offline machine-translation bridge (Apple Translation framework,
/// app-side). `from` is optional because the source may be auto-detected.
public protocol Translating: Sendable {
    func translate(_ text: String, from: String?, to: String) async throws -> String
}
