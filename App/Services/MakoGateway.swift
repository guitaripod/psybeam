import Foundation
import MidgarCore

/// mako calls the app makes itself, through the gateway at `/v1/intelligence/`: minting and settling a realtime
/// session, and deleting the account. AICredits makes the rest (identity, balance, purchases) against the same base
/// URL. The realtime media connection to the AI provider is not one of them and does not pass through here.
///
/// `Authorization` keeps the legacy api key, which is what mako knows the person by. When the Midgar ID can be had
/// quickly, its `midgarTokenHeader(within:)` rides next to it, which is how mako links the two. A call never
/// waits on or fails for the token: without one it goes with the api key alone.
nonisolated struct MakoGateway: Sendable {
    static let service = "intelligence"

    private let client: MidgarHTTPClient
    private let midgarHeaders: @Sendable () async -> [String: String]

    init(client: MidgarHTTPClient, midgarHeaders: @escaping @Sendable () async -> [String: String]) {
        self.client = client
        self.midgarHeaders = midgarHeaders
    }

    /// Sends a call authorized by `apiKey`, or by nothing when the route is public. Throws the client's error for any
    /// status outside 2xx. A call is sent once, because repeating a session mint or an account deletion that was
    /// already processed would charge or fail the person a second time.
    func send(
        _ method: MidgarHTTPMethod,
        path: String,
        apiKey: String? = nil,
        body: (any Encodable & Sendable)? = nil
    ) async throws(MidgarHTTPError) -> (Data, HTTPURLResponse) {
        let headers = await authorizationHeaders(apiKey: apiKey)
        let request = MidgarRequest(
            service: Self.service, path: path, method: method, headers: headers, body: body, neverRetries: true)
        return try await client.sendRaw(request)
    }

    /// The headers of a call: the Midgar token header when one is at hand, and the api key as a bearer.
    func authorizationHeaders(apiKey: String?) async -> [String: String] {
        var headers = await midgarHeaders()
        if let apiKey { headers["Authorization"] = "Bearer \(apiKey)" }
        return headers
    }
}

extension MidgarHTTPError {
    /// The HTTP status behind a failure, or 0 when the call never got an answer.
    nonisolated var statusCode: Int {
        switch self {
        case .unauthorized: 401
        case .paymentRequired: 402
        case .notFound: 404
        case .rateLimited: 429
        case .server(let status, _, _): status
        default: 0
        }
    }
}
