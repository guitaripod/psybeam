import Foundation
import PsybeamKit

final class WorkerClient: TranslationProviding {
    private let baseURL: URL
    private let keychain: KeychainStore
    private let session: URLSession

    init(baseURL: URL, keychain: KeychainStore, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.keychain = keychain
        self.session = session
    }

    func requestSession(pair: LanguagePair, direction: Side) async throws -> SessionToken {
        let body = SessionRequest(
            targetLanguage: pair.outputLanguage(for: direction),
            direction: direction.rawValue,
            estimatedMinutes: 1
        )
        let (data, response) = try await post("/v1/session", body: body, authorized: true)
        switch response.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SessionToken.self, from: data)
        case 401: throw CallError.server("unauthorized")
        case 429:
            let reason = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw reason == "quota_exhausted" ? CallError.quota : CallError.server(reason ?? "busy")
        case 422: throw CallError.unsupportedLanguage
        default: throw CallError.server("http_\(response.statusCode)")
        }
    }

    func reportUsage(sessionId: String, minutesUsed: Int) async {
        let body = UsageReport(sessionId: sessionId, minutesUsed: minutesUsed)
        _ = try? await post("/v1/session/usage", body: body, authorized: true)
    }

    struct Quota: Sendable {
        let dailyMinutes: Int
        let usedMinutes: Int
        let minutesRemaining: Int
    }

    func quota() async -> Quota? {
        guard let jwt = keychain.token() else { return nil }
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/me/quota"))
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        guard
            let (data, response) = try? await session.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let decoded = try? JSONDecoder().decode(QuotaResponse.self, from: data)
        else { return nil }
        return Quota(
            dailyMinutes: decoded.dailyMinutes,
            usedMinutes: decoded.usedMinutes,
            minutesRemaining: decoded.minutesRemaining
        )
    }

    private func post(_ path: String, body: some Encodable, authorized: Bool) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized {
            guard let jwt = keychain.token() else { throw CallError.server("not_authenticated") }
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CallError.network }
        return (data, http)
    }
}

private struct SessionRequest: Encodable {
    let targetLanguage: String
    let direction: String
    let estimatedMinutes: Int
}

private struct ErrorBody: Decodable {
    let error: String?
}

private struct QuotaResponse: Decodable {
    let dailyMinutes: Int
    let usedMinutes: Int
    let minutesRemaining: Int
}

private struct UsageReport: Encodable {
    let sessionId: String
    let minutesUsed: Int
}
