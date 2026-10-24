import Foundation
import PsybeamCore
import AICreditsCore
import MidgarCore

/// `TranslationProviding` backed by mako behind the gateway, and the billing
/// coordinator for the conversation. Each direction runs its own WebRTC leg with
/// its own session and `ek_`, but talk-time is summed across both legs and
/// rounded to whole minutes exactly ONCE: every `/settle` charges only the
/// increase in `ceil(totalSeconds / 60)` since the last settle, so a two-way
/// exchange is billed by real elapsed talk-time instead of per-leg rounded-up
/// (which over-charged whenever both sides spoke for sub-minute turns). An actor
/// because the two legs report concurrently into the shared running total.
///
/// A settle mako accepted changes the balance (the unused reservation comes back), so `onSettled` runs after each one
/// and the app reads the balance again.
actor CreditsTranslationProvider: TranslationProviding {
    private let apiKeyProvider: @Sendable () async throws -> String
    private let gateway: MakoGateway
    private let onSettled: @Sendable () async -> Void

    private var openSessions = 0
    private var conversationSeconds = 0
    private var billedMinutes = 0

    /// - Parameters:
    ///   - client: The AICredits client whose account's api key authorizes the calls.
    ///   - gateway: mako behind the gateway.
    ///   - onSettled: Runs after mako accepted a settle.
    init(
        client: AICreditsClient,
        gateway: MakoGateway = PsybeamMidgar.shared.mako,
        onSettled: @escaping @Sendable () async -> Void = {}
    ) {
        self.init(apiKey: { try await client.bootstrap().apiKey }, gateway: gateway, onSettled: onSettled)
    }

    init(
        apiKey: @escaping @Sendable () async throws -> String,
        gateway: MakoGateway,
        onSettled: @escaping @Sendable () async -> Void = {}
    ) {
        self.apiKeyProvider = apiKey
        self.gateway = gateway
        self.onSettled = onSettled
    }

    func requestSession(pair: LanguagePair, direction: Side) async throws -> SessionToken {
        let apiKey = try await apiKey()
        let language = pair.outputLanguage(for: direction)
        let reply = try await post(
            "v1/run/realtime.translate/start", apiKey: apiKey,
            body: ["language": language])

        switch reply.status {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let r = try decoder.decode(StartResponse.self, from: reply.data)
            registerStart()
            AppSettings.pendingSessionId = r.sessionId
            AppSettings.pendingReservedMinutes = r.reservedMinutes
            return SessionToken(
                provider: "openai",
                ephemeralToken: r.clientSecret,
                expiresAt: r.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    ?? Date().addingTimeInterval(60),
                sdpUrl: r.sdpUrl,
                model: r.model,
                targetLanguage: language,
                maxSessionSeconds: max(60, r.reservedMinutes * 60),
                sessionId: r.sessionId,
                minutesRemaining: r.balance / max(1, r.rateCredits))
        case 401:
            throw CallError.server("unauthorized")
        case 402:
            throw CallError.quota
        case 422:
            throw CallError.unsupportedLanguage
        default:
            throw CallError.server("http_\(reply.status)")
        }
    }

    func reportUsage(sessionId: String, secondsUsed: Int) async {
        let minutes = accrue(seconds: secondsUsed)
        await settle(sessionId: sessionId, minutes: minutes)
    }

    /// Settles a session that was reserved but never settled (app killed
    /// mid-call), charging the reserved minutes so the worker refunds whatever is
    /// unused. Bypasses the live talk-time total — it recovers a prior run.
    func settlePendingIfNeeded() async {
        guard let sessionId = AppSettings.pendingSessionId else { return }
        await settle(sessionId: sessionId, minutes: AppSettings.pendingReservedMinutes)
    }

    /// Resets the per-conversation talk-time totals when the first leg of a new
    /// conversation starts (no sessions currently open).
    private func registerStart() {
        if openSessions == 0 {
            conversationSeconds = 0
            billedMinutes = 0
        }
        openSessions += 1
    }

    /// Folds a leg's raw talk-time into the conversation total and returns the
    /// whole-minute delta to charge for it — the increase in `ceil(total / 60)`
    /// since the last settle. Summed across legs this is one rounding of the real
    /// elapsed talk-time, never per-leg over-rounding.
    private func accrue(seconds: Int) -> Int {
        conversationSeconds += max(0, seconds)
        let newBilled = conversationSeconds > 0
            ? Int((Double(conversationSeconds) / 60.0).rounded(.up))
            : 0
        let delta = max(0, newBilled - billedMinutes)
        billedMinutes = newBilled
        openSessions = max(0, openSessions - 1)
        return delta
    }

    private func settle(sessionId: String, minutes: Int) async {
        guard let apiKey = try? await apiKey() else { return }
        let result = try? await post(
            "v1/run/realtime.translate/settle", apiKey: apiKey,
            body: ["session_id": .string(sessionId), "minutes_used": .int(minutes)])
        guard result?.status == 200 else { return }
        if AppSettings.pendingSessionId == sessionId {
            clearPending()
        }
        await onSettled()
    }

    private func clearPending() {
        AppSettings.pendingSessionId = nil
        AppSettings.pendingReservedMinutes = 0
    }

    private func apiKey() async throws -> String {
        do {
            return try await apiKeyProvider()
        } catch {
            throw CallError.network
        }
    }

    /// One gateway answer: the body and the HTTP status, which the callers read the way the old direct calls did.
    private struct Reply {
        let data: Data
        let status: Int
    }

    /// Sends one call through the gateway. A status outside 2xx comes back as a reply for the caller to judge, as it
    /// always did; a call that never got an answer throws the matching `CallError`.
    private func post(_ path: String, apiKey: String, body: [String: JSONValue]) async throws -> Reply {
        do throws(MidgarHTTPError) {
            let (data, response) = try await gateway.send(.post, path: path, apiKey: apiKey, body: body)
            return Reply(data: data, status: response.statusCode)
        } catch {
            if case .cancelled = error { throw CallError.cancelled }
            guard error.statusCode > 0 else { throw CallError.network }
            return Reply(data: Data(), status: error.statusCode)
        }
    }

    private func post(_ path: String, apiKey: String, body: [String: String]) async throws -> Reply {
        try await post(path, apiKey: apiKey, body: body.mapValues { JSONValue.string($0) })
    }

    private struct StartResponse: Decodable {
        let sessionId: String
        let clientSecret: String
        let expiresAt: Int?
        let sdpUrl: String
        let model: String
        let reservedMinutes: Int
        let rateCredits: Int
        let balance: Int
    }
}
