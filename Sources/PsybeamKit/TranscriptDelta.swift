/// A streaming transcript fragment for one side of the conversation. Partial
/// deltas arrive with `isFinal == false`; the closing delta marks the turn.
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
