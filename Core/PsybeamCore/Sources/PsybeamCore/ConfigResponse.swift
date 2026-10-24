/// The `GET /v1/config` response. `supportedOutputLangs` is informational
/// server-config (the Worker's `OPENAI_TRANSLATE_OUTPUT_LANGS`), never compiled
/// into the binary and never a gate — Spike 1 verified the translate model
/// speaks 20+ languages, so there is no output-language ceiling to enforce.
public struct ConfigResponse: Sendable, Codable, Equatable {
    public var localLanguage: String?
    public var translateSupported: Bool
    public var recommendedPath: String
    public var supportedOutputLangs: [String]
    public var minutesRemaining: Int

    public init(
        localLanguage: String?,
        translateSupported: Bool,
        recommendedPath: String,
        supportedOutputLangs: [String],
        minutesRemaining: Int
    ) {
        self.localLanguage = localLanguage
        self.translateSupported = translateSupported
        self.recommendedPath = recommendedPath
        self.supportedOutputLangs = supportedOutputLangs
        self.minutesRemaining = minutesRemaining
    }
}
