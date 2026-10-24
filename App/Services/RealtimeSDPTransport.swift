import Foundation
import PsybeamCore

/// The one connection Psybeam makes to the AI provider itself rather than through the Midgar gateway: the WebRTC
/// offer and answer exchange. mako mints an ephemeral token and names the provider's SDP address; the phone posts its
/// offer there with that token, and the call's audio then flows peer to peer with the provider, never through Midgar's
/// servers. The registry lists the provider's host as this app's network exception.
nonisolated struct RealtimeSDPTransport: Sendable {
    /// Posts `offer` to `sdpUrl`, authorized by the session's ephemeral `ephemeralToken`, and returns the answer SDP.
    func answer(for offer: String, at sdpUrl: String, ephemeralToken: String) async throws -> String {
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
}
