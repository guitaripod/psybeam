import Foundation
import PsybeamKit
import AICreditsCore

/// `TranslationProviding` backed by the shared AICredits worker, and the billing
/// coordinator for the conversation. Each direction runs its own WebRTC leg with
/// its own session and `ek_`, but talk-time is summed across both legs and
/// rounded to whole minutes exactly ONCE: every `/settle` charges only the
/// increase in `ceil(totalSeconds / 60)` since the last settle, so a two-way
/// exchange is billed by real elapsed talk-time instead of per-leg rounded-up
/// (which over-charged whenever both sides spoke for sub-minute turns). An actor
/// because the two legs report concurrently into the shared running total.
actor CreditsTranslationProvider: TranslationProviding {
    private let client: AICreditsClient
    private let baseURL: URL
    private let appID = "psybeam"

    private var openSessions = 0
    private var conversationSeconds = 0
    private var billedMinutes = 0

    init(client: AICreditsClient, baseURL: URL) {
        self.client = client
        self.baseURL = baseURL
    }

    func requestSession(pair: LanguagePair, direction: Side) async throws -> SessionToken {
        let apiKey = try await apiKey()
        let language = pair.outputLanguage(for: direction)
        let (data, http) = try await post(
            "v1/run/realtime.translate/start", apiKey: apiKey,
            body: ["language": language])

        switch http.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let r = try decoder.decode(StartResponse.self, from: data)
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
            throw CallError.server("http_\(http.statusCode)")
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
        if result?.1.statusCode == 200, AppSettings.pendingSessionId == sessionId {
            clearPending()
        }
    }

    private func clearPending() {
        AppSettings.pendingSessionId = nil
        AppSettings.pendingReservedMinutes = 0
    }

    private func apiKey() async throws -> String {
        do {
            return try await client.bootstrap().apiKey
        } catch {
            throw CallError.network
        }
    }

    private func post(_ path: String, apiKey: String, body: [String: JSONValue]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(appID, forHTTPHeaderField: "X-App-ID")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CallError.network }
        return (data, http)
    }

    private func post(_ path: String, apiKey: String, body: [String: String]) async throws -> (Data, HTTPURLResponse) {
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
