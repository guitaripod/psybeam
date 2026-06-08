import AVFoundation
import Foundation
import PsybeamKit
import WebRTC

actor RealtimeCallService: RealtimeCallProviding {
    nonisolated let states: AsyncStream<CallState>
    nonisolated let transcripts: AsyncStream<TranscriptDelta>
    nonisolated let levels: AsyncStream<Float>

    private let stateCont: AsyncStream<CallState>.Continuation
    private let transcriptCont: AsyncStream<TranscriptDelta>.Continuation
    private let levelCont: AsyncStream<Float>.Continuation
    private let translationProvider: TranslationProviding
    private let factory: RTCPeerConnectionFactory

    private var pc: RTCPeerConnection?
    private var audioTrack: RTCAudioTrack?
    private var dataChannel: RTCDataChannel?
    private var coordinator: CallCoordinator?
    private var sessionId: String?
    private var currentSessionId: String?
    private var didActivateMic = false
    private var activeSeconds: TimeInterval = 0
    private var micActiveStart: Date?
    private var levelTask: Task<Void, Never>?

    nonisolated(unsafe) private static let sharedFactory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory()
    }()

    init(translationProvider: TranslationProviding) {
        self.translationProvider = translationProvider
        self.factory = Self.sharedFactory

        var sc: AsyncStream<CallState>.Continuation!
        self.states = AsyncStream { sc = $0 }
        self.stateCont = sc

        var tc: AsyncStream<TranscriptDelta>.Continuation!
        self.transcripts = AsyncStream { tc = $0 }
        self.transcriptCont = tc

        var lc: AsyncStream<Float>.Continuation!
        self.levels = AsyncStream { lc = $0 }
        self.levelCont = lc
    }

    func connect(spec: TranslationSessionSpec) async throws {
        stateCont.yield(.connecting)
        let token = try await translationProvider.requestSession(pair: spec.pair, direction: spec.direction)

        currentSessionId = token.sessionId
        didActivateMic = false
        activeSeconds = 0
        micActiveStart = nil

        do {
            Self.configureAudioSession()

            let config = RTCConfiguration()
            config.sdpSemantics = .unifiedPlan
            config.iceServers = []
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            let coordinator = CallCoordinator(
                stateCont: stateCont,
                transcriptCont: transcriptCont,
                direction: spec.direction
            )
            guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: coordinator) else {
                throw CallError.network
            }
            self.coordinator = coordinator
            self.pc = pc

            let source = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
            let track = factory.audioTrack(with: source, trackId: "mic0")
            track.isEnabled = false
            pc.add(track, streamIds: ["psybeam0"])
            self.audioTrack = track

            if let dc = pc.dataChannel(forLabel: "oai-events", configuration: RTCDataChannelConfiguration()) {
                dc.delegate = coordinator
                self.dataChannel = dc
            }

            let offerSDP = try await makeOffer(pc: pc, constraints: constraints)
            try await setLocal(pc: pc, sdp: RTCSessionDescription(type: .offer, sdp: offerSDP))
            let answerSDP = try await exchangeSDP(sdpUrl: token.sdpUrl, ephemeralToken: token.ephemeralToken, offer: offerSDP)
            try await setRemote(pc: pc, sdp: RTCSessionDescription(type: .answer, sdp: answerSDP))
        } catch {
            cleanupPeer()
            await reportAndClear(minutes: 0)
            throw error
        }

        self.sessionId = token.sessionId
        startMetering()
        AppLogger.shared.info("webrtc connected session=\(token.sessionId) lang=\(token.targetLanguage)", category: .webrtc)
    }

    private func startMetering() {
        levelTask?.cancel()
        levelTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func tick() async {
        levelCont.yield(await pollLevel())
    }

    private func pollLevel() async -> Float {
        guard let pc else { return 0 }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Float, Never>) in
            pc.statistics { report in
                var peak = 0.0
                for (_, stat) in report.statistics {
                    if let number = stat.values["audioLevel"] as? NSNumber {
                        peak = max(peak, number.doubleValue)
                    }
                }
                continuation.resume(returning: Float(peak))
            }
        }
    }

    func setMicActive(_ active: Bool) {
        audioTrack?.isEnabled = active
        if active {
            didActivateMic = true
            if micActiveStart == nil { micActiveStart = Date() }
        } else if let start = micActiveStart {
            activeSeconds += Date().timeIntervalSince(start)
            micActiveStart = nil
        }
    }

    func setTurn(_ side: Side) async {}

    func bargeIn() async {}

    func hangUp() async {
        let minutes = elapsedMinutes()
        cleanupPeer()
        levelCont.yield(0)
        await reportAndClear(minutes: minutes)
        stateCont.yield(.ended)
    }

    private func cleanupPeer() {
        levelTask?.cancel()
        levelTask = nil
        audioTrack?.isEnabled = false
        dataChannel?.close()
        pc?.close()
        pc = nil
        dataChannel = nil
        audioTrack = nil
        coordinator = nil
    }

    private func reportAndClear(minutes: Int) async {
        if let currentSessionId {
            await translationProvider.reportUsage(sessionId: currentSessionId, minutesUsed: minutes)
        }
        currentSessionId = nil
        micActiveStart = nil
        activeSeconds = 0
    }

    /// Billed minutes = the time the mic was actually live (hold-to-talk windows),
    /// not idle warm-connection time. Each leg only accrues while its button is
    /// held, so the two legs sum to real conversation minutes rather than 2x.
    private func elapsedMinutes() -> Int {
        guard didActivateMic else { return 0 }
        var total = activeSeconds
        if let micActiveStart { total += Date().timeIntervalSince(micActiveStart) }
        guard total > 0 else { return 0 }
        return max(1, Int(ceil(total / 60.0)))
    }

    private func makeOffer(pc: RTCPeerConnection, constraints: RTCMediaConstraints) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            pc.offer(for: constraints) { sdp, error in
                if let sdp {
                    continuation.resume(returning: sdp.sdp)
                } else {
                    continuation.resume(throwing: error ?? CallError.network)
                }
            }
        }
    }

    private func setLocal(pc: RTCPeerConnection, sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(sdp) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private func setRemote(pc: RTCPeerConnection, sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(sdp) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private func exchangeSDP(sdpUrl: String, ephemeralToken: String, offer: String) async throws -> String {
        guard let url = URL(string: sdpUrl) else { throw CallError.network }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(ephemeralToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(offer.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let http = response as? HTTPURLResponse,
            (200...201).contains(http.statusCode),
            let answer = String(data: data, encoding: .utf8)
        else {
            throw CallError.server("sdp_exchange_failed")
        }
        return answer
    }

    /// `.voiceChat` engages Apple's Voice-Processing I/O unit, which runs hardware
    /// echo-cancellation, noise-suppression and auto-gain — and is what makes the
    /// system Voice Isolation mic mode available to the user for noisy rooms.
    /// WebRTC's software-APM `goog*` constraints are intentionally NOT set: VPIO
    /// owns the processing on iOS, so those constraints are inert here.
    private static func configureAudioSession() {
        let config = RTCAudioSessionConfiguration.webRTC()
        config.category = AVAudioSession.Category.playAndRecord.rawValue
        config.categoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
        config.mode = AVAudioSession.Mode.voiceChat.rawValue
        RTCAudioSessionConfiguration.setWebRTC(config)
    }
}

private struct OAIEvent: Decodable {
    let type: String
    let delta: String?
}

private final class CallCoordinator: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate, @unchecked Sendable {
    private let stateCont: AsyncStream<CallState>.Continuation
    private let transcriptCont: AsyncStream<TranscriptDelta>.Continuation
    private let direction: Side

    init(
        stateCont: AsyncStream<CallState>.Continuation,
        transcriptCont: AsyncStream<TranscriptDelta>.Continuation,
        direction: Side
    ) {
        self.stateCont = stateCont
        self.transcriptCont = transcriptCont
        self.direction = direction
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .connected, .completed: stateCont.yield(.live(turn: direction))
        case .failed: stateCont.yield(.failed(.network))
        case .disconnected: stateCont.yield(.reconnecting)
        case .closed: stateCont.yield(.ended)
        default: break
        }
    }

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {}

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let event = try? JSONDecoder().decode(OAIEvent.self, from: buffer.data) else { return }
        let isFinal = event.type.hasSuffix(".done")
        if event.type.contains("output_transcript") {
            transcriptCont.yield(TranscriptDelta(side: direction.other, text: event.delta ?? "", isFinal: isFinal))
        } else if event.type.contains("input_transcript") {
            transcriptCont.yield(TranscriptDelta(side: direction, text: event.delta ?? "", isFinal: isFinal))
        }
    }
}
