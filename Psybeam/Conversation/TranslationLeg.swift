import Combine
import Foundation
import PsybeamKit

/// One direction of the conversation: a `speaker` side, a dedicated WebRTC
/// session whose output language is the *other* side's, and the streamed
/// translation that the listener reads. Both legs share the mic (only the
/// holding leg is unmuted), so the two halves stay turn-gated.
@MainActor
final class TranslationLeg {
    let statePublisher = PassthroughSubject<TranslationState, Never>()
    let textPublisher = PassthroughSubject<String, Never>()
    let sourcePublisher = PassthroughSubject<String, Never>()
    let finishedPublisher = PassthroughSubject<Void, Never>()
    let amplitudePublisher = PassthroughSubject<Float, Never>()

    let speaker: Side
    var pair: LanguagePair

    private let call: RealtimeCallService
    private var connected = false
    private var holding = false
    private var connectTask: Task<Bool, Never>?
    private var text = ""
    private var source = ""

    init(call: RealtimeCallService, speaker: Side, pair: LanguagePair) {
        self.call = call
        self.speaker = speaker
        self.pair = pair
        observe()
    }

    var isHolding: Bool { holding }

    func warmUp() {
        Task { _ = await ensureConnected() }
    }

    func holdDown() {
        holding = true
        text = ""
        source = ""
        textPublisher.send("")
        sourcePublisher.send("")
        statePublisher.send(connected ? .listening(turn: speaker, level: 0.7) : .processing(from: speaker))
        Task {
            let ready = await ensureConnected()
            guard holding else { return }
            if ready {
                await call.setMicActive(true)
                statePublisher.send(.listening(turn: speaker, level: 0.7))
            } else {
                statePublisher.send(.error(.network))
                holding = false
            }
        }
    }

    func holdUp() {
        guard holding else { return }
        holding = false
        statePublisher.send(.idle)
        Task { await call.setMicActive(false) }
    }

    func setPair(_ newPair: LanguagePair) {
        pair = newPair
        connectTask?.cancel()
        connectTask = nil
        connected = false
        statePublisher.send(.idle)
        Task {
            await call.hangUp()
            _ = await ensureConnected()
        }
    }

    func end() {
        connectTask?.cancel()
        connectTask = nil
        connected = false
        Task { await call.hangUp() }
    }

    private func ensureConnected() async -> Bool {
        if connected { return true }
        if let connectTask { return await connectTask.value }
        let call = call
        let speaker = speaker
        let pair = pair
        let task = Task { () -> Bool in
            do {
                try await call.connect(spec: TranslationSessionSpec(pair: pair, direction: speaker, sessionId: UUID().uuidString))
                return true
            } catch {
                AppLogger.shared.error("leg(\(speaker)) connect failed: \(error)", category: .session)
                return false
            }
        }
        connectTask = task
        let ok = await task.value
        connectTask = nil
        connected = ok
        return ok
    }

    private func observe() {
        let states = call.states
        let transcripts = call.transcripts
        let levels = call.levels
        Task { [weak self] in for await state in states { self?.handle(callState: state) } }
        Task { [weak self] in for await delta in transcripts { self?.handle(delta: delta) } }
        Task { [weak self] in for await level in levels { self?.amplitudePublisher.send(level) } }
    }

    private func handle(callState: CallState) {
        switch callState {
        case .failed:
            statePublisher.send(.error(.network))
            connected = false
        case .reconnecting:
            statePublisher.send(.reconnecting)
        case .ended:
            connected = false
        default:
            break
        }
    }

    private func handle(delta: TranscriptDelta) {
        if delta.side == speaker.other {
            text += delta.text
            textPublisher.send(text)
            if delta.isFinal, !text.isEmpty { finishedPublisher.send(()) }
        } else if delta.side == speaker {
            source += delta.text
            sourcePublisher.send(source)
        }
    }
}
