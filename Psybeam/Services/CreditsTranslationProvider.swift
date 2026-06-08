import Foundation
import PsybeamKit
import AICreditsCore

/// `TranslationProviding` backed by the shared AICredits worker. Replaces the
/// per-app token mint + daily quota: `/v1/run/realtime.translate/start` reserves
/// credits and mints the OpenAI `ek_`; `/settle` refunds the unused minutes.
/// The WebRTC layer (`RealtimeCallService`) is unchanged — it only sees a `SessionToken`.
final class CreditsTranslationProvider: TranslationProviding {
    private let client: AICreditsClient
    private let baseURL: URL
    private let appID = "psybeam"

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

    func reportUsage(sessionId: String, minutesUsed: Int) async {
        guard let apiKey = try? await apiKey() else { return }
        let result = try? await post(
            "v1/run/realtime.translate/settle", apiKey: apiKey,
            body: ["session_id": .string(sessionId), "minutes_used": .int(minutesUsed)])
        if result?.1.statusCode == 200, AppSettings.pendingSessionId == sessionId {
            clearPending()
        }
    }

    /// Settles a session that was reserved but never settled (app killed mid-call),
    /// charging the reserved minutes so the worker refunds whatever is unused.
    func settlePendingIfNeeded() async {
        guard let sessionId = AppSettings.pendingSessionId else { return }
        await reportUsage(sessionId: sessionId, minutesUsed: AppSettings.pendingReservedMinutes)
        clearPending()
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
