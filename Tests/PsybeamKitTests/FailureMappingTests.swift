import Testing
@testable import PsybeamKit

@Suite("Failure mapping is cause-accurate")
struct FailureMappingTests {
    @Test("Quota is its own state, never a retryable error")
    func quota() {
        #expect(TranslationState.failure(for: .quota, isOnline: true) == .quotaExhausted)
        #expect(TranslationState.failure(for: .quota, isOnline: false) == .quotaExhausted)
        // A quota failure must NOT collapse into the generic retry state.
        #expect(TranslationState.failure(for: .quota, isOnline: true) != .error(.network))
    }

    @Test("Permission denial carries the specific permission")
    func permission() {
        #expect(TranslationState.failure(for: .permission(.microphone), isOnline: true) == .permissionDenied(.microphone))
    }

    @Test("Unsupported language is named, not a generic error")
    func unsupportedLanguage() {
        #expect(TranslationState.failure(for: .unsupportedLanguage, isOnline: true) == .error(.unsupportedLanguage))
    }

    @Test("Server failure is a retryable error, preserving the reason")
    func server() {
        #expect(TranslationState.failure(for: .server("boom"), isOnline: true) == .error(.server("boom")))
    }

    @Test("Network only reads as offline when the OS confirms no path")
    func networkVsOffline() {
        #expect(TranslationState.failure(for: .network, isOnline: false) == .offline)
        #expect(TranslationState.failure(for: .network, isOnline: true) == .error(.network))
        // We never claim offline while online — that would be a hallucinated cause.
        #expect(TranslationState.failure(for: .network, isOnline: true) != .offline)
    }

    @Test("Cancellation shows nothing")
    func cancelled() {
        #expect(TranslationState.failure(for: .cancelled, isOnline: true) == nil)
        #expect(TranslationState.failure(for: .cancelled, isOnline: false) == nil)
    }
}
