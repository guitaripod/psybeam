import Testing
@testable import PsybeamCore

@Suite("Model features are hidden where Midgar refuses model calls")
struct ModelFeatureVisibilityTests {
    @Test("Every model surface is shown while models are available")
    func availableShowsEverything() {
        let features = ModelFeatureVisibility(modelsAvailable: true)
        #expect(features.showsTalkButtons)
        #expect(features.showsSessionNotice)
        #expect(features.offersOnboarding)
        #expect(features.offersPurchases)
        #expect(features.startsSessions)
        #expect(!features.showsRegionLine)
    }

    @Test("Every model surface is hidden, and the region line shown, where models are refused")
    func refusedHidesEverything() {
        let features = ModelFeatureVisibility(modelsAvailable: false)
        #expect(!features.showsTalkButtons)
        #expect(!features.showsSessionNotice)
        #expect(!features.offersOnboarding)
        #expect(!features.offersPurchases)
        #expect(!features.startsSessions)
        #expect(features.showsRegionLine)
    }

    @Test("A refused call maps to the region state, never a retryable error")
    func refusalMapsToRegionState() {
        #expect(TranslationState.failure(for: .unavailableInRegion, isOnline: true) == .unavailableInRegion)
        #expect(TranslationState.failure(for: .unavailableInRegion, isOnline: false) == .unavailableInRegion)
        #expect(TranslationState.failure(for: .unavailableInRegion, isOnline: true) != .error(.network))
    }
}
