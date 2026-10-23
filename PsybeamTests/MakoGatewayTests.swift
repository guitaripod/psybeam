import Foundation
import MidgarCore
import Testing
@testable import Psybeam

@Suite(.serialized)
struct MakoGatewayTests {

    @Test func aSessionMintGoesToMakoBehindTheGatewayWithTheApiKeyAndTheMidgarToken() async throws {
        let capture = StubbedResponses.install(status: 200, body: Data("{}".utf8))
        let gateway = MakoGateway(client: client(), midgarToken: { "midgar-access" })

        let (_, response) = try await gateway.send(
            .post, path: "v1/run/realtime.translate/start", apiKey: "legacy-key", body: ["language": "ja"])

        let request = try #require(capture.requests.first)
        #expect(response.statusCode == 200)
        #expect(request.url?.absoluteString == "https://api.midgarcorp.cc/v1/intelligence/v1/run/realtime.translate/start")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer legacy-key")
        #expect(request.value(forHTTPHeaderField: "X-Midgar-Token") == "midgar-access")
        #expect(request.value(forHTTPHeaderField: "X-App-ID") == "psybeam")
    }

    @Test func aCallWithoutAMidgarTokenGoesWithTheApiKeyAlone() async throws {
        let capture = StubbedResponses.install(status: 200, body: Data("{}".utf8))
        let gateway = MakoGateway(client: client(), midgarToken: { nil })

        _ = try await gateway.send(
            .post, path: "v1/run/realtime.translate/settle", apiKey: "legacy-key",
            body: ["session_id": "rt_1"])

        let request = try #require(capture.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer legacy-key")
        #expect(request.value(forHTTPHeaderField: "X-Midgar-Token") == nil)
    }

    @Test func anAccountDeletionIsSentOnceEvenWhenTheServerFails() async {
        let capture = StubbedResponses.install(status: 503, body: Data())
        let gateway = MakoGateway(client: client(), midgarToken: { nil })

        await #expect(throws: MidgarHTTPError.self) {
            _ = try await gateway.send(.delete, path: "v1/identity", apiKey: "legacy-key")
        }
        #expect(capture.requests.count == 1)
        #expect(capture.requests.first?.url?.absoluteString == "https://api.midgarcorp.cc/v1/intelligence/v1/identity")
    }

    @Test func aRefusedCallReportsItsStatus() async {
        StubbedResponses.install(status: 402, body: Data(#"{"error":{"code":"insufficient_credits","message":"no"}}"#.utf8))
        let gateway = MakoGateway(client: client(), midgarToken: { nil })

        await #expect(throws: MidgarHTTPError.self) {
            _ = try await gateway.send(.post, path: "v1/run/realtime.translate/start", apiKey: "legacy-key", body: ["language": "ja"])
        }
        #expect(MidgarHTTPError.paymentRequired(code: nil).statusCode == 402)
        #expect(MidgarHTTPError.unauthorized(code: nil).statusCode == 401)
        #expect(MidgarHTTPError.server(status: 422, code: nil, message: "").statusCode == 422)
        #expect(MidgarHTTPError.offline.statusCode == 0)
    }

    @Test func aiCreditsPathsLandOnMakosRoutesThroughTheGateway() {
        let url = PsybeamMidgar.intelligenceURL.appendingPathComponent("/v1/credits/balance")
        #expect(url.absoluteString == "https://api.midgarcorp.cc/v1/intelligence/v1/credits/balance")
        #expect(AICreditsManager.shared.baseURL == PsybeamMidgar.intelligenceURL)
    }

    @Test func aHostThatReachesNoMidgarServiceSendsNoToken() {
        #expect(PsybeamMidgar.reachesMidgarServices == false)
    }

    private func client() -> MidgarHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubbedResponses.self]
        let http = MidgarHTTPConfiguration(appID: PsybeamMidgar.appID, session: URLSession(configuration: configuration))
        return MidgarHTTPClient(configuration: http)
    }
}

/// Answers every request with one canned response and remembers what it was asked.
final class StubbedResponses: URLProtocol {
    /// Collects the requests the stub saw. Reads and writes happen under one lock.
    final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [URLRequest] = []

        var requests: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return seen
        }

        func record(_ request: URLRequest) {
            lock.lock()
            seen.append(request)
            lock.unlock()
        }
    }

    private struct Canned {
        var status: Int
        var body: Data
        var capture: Capture
    }

    /// The canned response of the running test. The suite is serialized, so one test owns it at a time.
    private nonisolated(unsafe) static var canned = Canned(status: 200, body: Data(), capture: Capture())

    @discardableResult
    static func install(status: Int, body: Data) -> Capture {
        let capture = Capture()
        canned = Canned(status: status, body: body, capture: capture)
        return capture
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let canned = Self.canned
        canned.capture.record(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: canned.status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: canned.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
