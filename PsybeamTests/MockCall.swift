import PsybeamKit

/// A drivable `RealtimeCallProviding` for testing `TranslationLeg` without WebRTC.
/// Connect can be made to throw a chosen `CallError`; the three streams can be fed
/// states/transcripts/levels on demand. All access is from the test's MainActor,
/// so `@unchecked Sendable` is sound here.
final class MockCall: RealtimeCallProviding, @unchecked Sendable {
    let states: AsyncStream<CallState>
    let transcripts: AsyncStream<TranscriptDelta>
    let levels: AsyncStream<Float>

    private let stateCont: AsyncStream<CallState>.Continuation
    private let transcriptCont: AsyncStream<TranscriptDelta>.Continuation
    private let levelCont: AsyncStream<Float>.Continuation

    var connectError: CallError?
    private(set) var micActive = false
    private(set) var connectCount = 0
    private(set) var hangUpCount = 0

    init() {
        var sc: AsyncStream<CallState>.Continuation!
        states = AsyncStream { sc = $0 }
        stateCont = sc
        var tc: AsyncStream<TranscriptDelta>.Continuation!
        transcripts = AsyncStream { tc = $0 }
        transcriptCont = tc
        var lc: AsyncStream<Float>.Continuation!
        levels = AsyncStream { lc = $0 }
        levelCont = lc
    }

    func connect(spec: TranslationSessionSpec) async throws {
        connectCount += 1
        if let connectError { throw connectError }
    }

    func setMicActive(_ active: Bool) async { micActive = active }
    func setTurn(_ side: Side) async {}
    func bargeIn() async {}
    func hangUp() async { hangUpCount += 1 }

    func emit(_ state: CallState) { stateCont.yield(state) }
    func emit(_ delta: TranscriptDelta) { transcriptCont.yield(delta) }
    func emit(level: Float) { levelCont.yield(level) }
}
