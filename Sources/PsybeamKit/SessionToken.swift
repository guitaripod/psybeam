import Foundation

/// The session token the call layer consumes, assembled from mako's
/// `/v1/run/realtime.translate/start` response. `ephemeralToken` is the OpenAI
/// `ek_` client secret the device exchanges for an SDP answer directly — the
/// audio never traverses our infrastructure.
public struct SessionToken: Sendable, Codable, Equatable {
    public var provider: String
    public var ephemeralToken: String
    public var expiresAt: Date
    public var sdpUrl: String
    public var model: String
    public var targetLanguage: String
    public var maxSessionSeconds: Int
    public var sessionId: String
    public var minutesRemaining: Int

    public init(
        provider: String,
        ephemeralToken: String,
        expiresAt: Date,
        sdpUrl: String,
        model: String,
        targetLanguage: String,
        maxSessionSeconds: Int,
        sessionId: String,
        minutesRemaining: Int
    ) {
        self.provider = provider
        self.ephemeralToken = ephemeralToken
        self.expiresAt = expiresAt
        self.sdpUrl = sdpUrl
        self.model = model
        self.targetLanguage = targetLanguage
        self.maxSessionSeconds = maxSessionSeconds
        self.sessionId = sessionId
        self.minutesRemaining = minutesRemaining
    }
}
