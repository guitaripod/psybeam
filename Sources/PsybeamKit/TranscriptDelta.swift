/// A streaming transcript fragment for one side of the conversation. `isFinal`
/// marks a transport-declared end of turn — the OpenAI translations transport
/// never declares one, so consumers must also treat quiescence as the close.
public struct TranscriptDelta: Sendable, Equatable, Codable {
    public var side: Side
    public var text: String
    public var isFinal: Bool

    public init(side: Side, text: String, isFinal: Bool) {
        self.side = side
        self.text = text
        self.isFinal = isFinal
    }
}
