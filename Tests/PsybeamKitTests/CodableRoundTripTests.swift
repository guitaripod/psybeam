import Foundation
import Testing
@testable import PsybeamKit

@Suite("Codable round-trip")
struct CodableRoundTripTests {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    @Test("SessionToken survives an encode/decode round-trip")
    func sessionToken() throws {
        let token = SessionToken(
            provider: "openai",
            ephemeralToken: "ek_test_123",
            expiresAt: Date(timeIntervalSince1970: 1_780_000_000),
            sdpUrl: "https://api.openai.com/v1/realtime/translations/calls",
            model: "gpt-realtime-translate",
            targetLanguage: "es",
            maxSessionSeconds: 3600,
            sessionId: "sess_abc",
            minutesRemaining: 7
        )
        #expect(try roundTrip(token) == token)
    }

    @Test("SessionToken decodes the exact Worker JSON field names")
    func sessionTokenWireShape() throws {
        let json = """
        {
          "provider": "openai",
          "ephemeralToken": "ek_xyz",
          "expiresAt": "2026-06-06T12:00:00Z",
          "sdpUrl": "https://api.openai.com/v1/realtime/translations/calls",
          "model": "gpt-realtime-translate",
          "targetLanguage": "ja",
          "maxSessionSeconds": 3600,
          "sessionId": "sess_1",
          "minutesRemaining": 10
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let token = try decoder.decode(SessionToken.self, from: Data(json.utf8))
        #expect(token.ephemeralToken == "ek_xyz")
        #expect(token.targetLanguage == "ja")
        #expect(token.maxSessionSeconds == 3600)
    }

    @Test("ConfigResponse survives a round-trip, including nil localLanguage")
    func configResponse() throws {
        let supported = ConfigResponse(
            localLanguage: "fr",
            translateSupported: true,
            recommendedPath: "openai",
            supportedOutputLangs: ["es", "fr", "de"],
            minutesRemaining: 10
        )
        let gap = ConfigResponse(
            localLanguage: nil,
            translateSupported: false,
            recommendedPath: "openai",
            supportedOutputLangs: [],
            minutesRemaining: 0
        )
        #expect(try roundTrip(supported) == supported)
        #expect(try roundTrip(gap) == gap)
    }

    @Test("TranslationSessionSpec and LanguagePair round-trip")
    func specRoundTrip() throws {
        let spec = TranslationSessionSpec(
            pair: LanguagePair(traveler: "en", local: "fr"),
            direction: .traveler,
            sessionId: "sess_42"
        )
        #expect(try roundTrip(spec) == spec)
        #expect(spec.outputLanguage == "fr")
    }

    @Test("Side encodes to its raw string")
    func sideRawValue() throws {
        let data = try JSONEncoder().encode(Side.local)
        #expect(String(decoding: data, as: UTF8.self) == "\"local\"")
    }
}
