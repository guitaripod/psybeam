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

    private let call: any RealtimeCallProviding
    private var connected = false
    private var holding = false
    private var holdGeneration = 0
    private var connectTask: Task<CallError?, Never>?
    private var armingTask: Task<Void, Never>?
    private var reconnectTimer: Task<Void, Never>?
    private var text = ""
    private var source = ""

    init(call: any RealtimeCallProviding, speaker: Side, pair: LanguagePair) {
        self.call = call
        self.speaker = speaker
        self.pair = pair
        observe()
    }

    var isHolding: Bool { holding }

    func warmUp() {
        Task { _ = await ensureConnected() }
    }

    /// Emit `.listening` only once the mic is genuinely live (`setMicActive`
    /// returned), never optimistically — a silently-dead warm session must not
    /// look like it's recording. The interim "arming"/"connecting" state shows
    /// only if that takes longer than a frame's worth of grace, so the common
    /// warm path goes straight to listening and still feels instant.
    func holdDown() {
        holdGeneration &+= 1
        let gen = holdGeneration
        holding = true
        text = ""
        source = ""
        textPublisher.send("")
        sourcePublisher.send("")
        armingTask?.cancel()
        armingTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, self.holding, gen == self.holdGeneration else { return }
            self.statePublisher.send(self.connected ? .armed(turn: self.speaker) : .processing(from: self.speaker))
        }
        Task {
            let failure = await ensureConnected()
            guard holding, gen == holdGeneration else { return }
            armingTask?.cancel()
            if let failure {
                if let state = TranslationState.failure(for: failure, isOnline: NetworkMonitor.shared.isOnline) {
                    statePublisher.send(state)
                }
                holding = false
            } else {
                await call.setMicActive(true)
                guard holding, gen == holdGeneration else { return }
                statePublisher.send(.listening(turn: speaker, level: 0))
            }
        }
    }

    func holdUp() {
        guard holding else { return }
        holdGeneration &+= 1
        holding = false
        armingTask?.cancel()
        statePublisher.send(.idle)
        Task { await call.setMicActive(false) }
    }

    /// Only re-mint when THIS leg's own output language actually changed, and
    /// only if it had a live or in-flight session worth replacing. A GPS or
    /// manual change to the *other* side's language updates the stored pair but
    /// must not tear this leg's warm session down. A cold leg simply adopts the
    /// new pair — `warmUp()`/`holdDown()` connects it with the right language —
    /// so we never mint a stale-language session just to cancel it on the next
    /// GPS result (the warm-up-before-GPS race).
    func setPair(_ newPair: LanguagePair) {
        let outputChanged = newPair.outputLanguage(for: speaker) != pair.outputLanguage(for: speaker)
        pair = newPair
        guard outputChanged else { return }
        let wasActive = connected || connectTask != nil
        connectTask?.cancel()
        connectTask = nil
        reconnectTimer?.cancel()
        reconnectTimer = nil
        connected = false
        guard wasActive else { return }
        statePublisher.send(.idle)
        Task {
            await call.hangUp()
            _ = await ensureConnected()
        }
    }

    func end() {
        connectTask?.cancel()
        connectTask = nil
        armingTask?.cancel()
        reconnectTimer?.cancel()
        reconnectTimer = nil
        connected = false
        Task { await call.hangUp() }
    }

    /// Returns nil on success, or the precise `CallError` so the UI can show an
    /// honest, cause-specific state — never a guessed one.
    private func ensureConnected() async -> CallError? {
        if connected { return nil }
        if let connectTask { return await connectTask.value }
        let call = call
        let speaker = speaker
        let pair = pair
        let task = Task { () -> CallError? in
            do {
                try await call.connect(spec: TranslationSessionSpec(pair: pair, direction: speaker, sessionId: UUID().uuidString))
                return nil
            } catch is CancellationError {
                return Self.cancelled(speaker)
            } catch let error as URLError where error.code == .cancelled {
                return Self.cancelled(speaker)
            } catch let error as CallError {
                if error == .cancelled { return Self.cancelled(speaker) }
                AppLogger.shared.error("leg(\(speaker)) connect failed: \(error)", category: .session)
                return error
            } catch {
                AppLogger.shared.error("leg(\(speaker)) connect failed: \(error)", category: .session)
                return .network
            }
        }
        connectTask = task
        let result = await task.value
        connectTask = nil
        connected = (result == nil)
        return result
    }

    /// A connect torn down by a language change or session end is routine, not a
    /// failure: logged at debug to stay out of the error stream, and mapped to
    /// no UI state via `TranslationState.failure(for: .cancelled)`.
    private static func cancelled(_ speaker: Side) -> CallError {
        AppLogger.shared.debug("leg(\(speaker)) connect cancelled", category: .session)
        return .cancelled
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
        case .live:
            connected = true
            reconnectTimer?.cancel()
            reconnectTimer = nil
        case .reconnecting:
            statePublisher.send(.reconnecting)
            startReconnectDeadline()
        case .failed(let error):
            reconnectTimer?.cancel()
            reconnectTimer = nil
            connected = false
            if holding, let state = TranslationState.failure(for: error, isOnline: NetworkMonitor.shared.isOnline) {
                statePublisher.send(state)
                holding = false
            }
        case .ended:
            connected = false
            reconnectTimer?.cancel()
            reconnectTimer = nil
        default:
            break
        }
    }

    /// ICE reconnect is routine, but it must not hang amber forever: if it hasn't
    /// recovered in 6s, tear the peer down so the next hold mints fresh, and show
    /// an honest failure (offline only if the OS confirms no path).
    private func startReconnectDeadline() {
        reconnectTimer?.cancel()
        reconnectTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled else { return }
            self.connected = false
            await self.call.hangUp()
            guard self.holding else { return }
            self.statePublisher.send(NetworkMonitor.shared.isOnline ? .error(.network) : .offline)
            self.holding = false
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
