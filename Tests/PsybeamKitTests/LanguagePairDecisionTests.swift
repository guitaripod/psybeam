import Testing
@testable import PsybeamKit

@Suite("Language pair decisions")
struct LanguagePairDecisionTests {
    @Test("A GPS fix that resolves to your own language is ignored as being at home")
    func atHomeIsIgnored() {
        let pair = LanguagePair(traveler: "en", local: "ja")
        #expect(pair.applyingDetectedLocal("en") == nil)
    }

    @Test("At home is judged on the base language, not the full tag")
    func atHomeIgnoresRegionAndScript() {
        #expect(LanguagePair(traveler: "pt-BR", local: "es").applyingDetectedLocal("pt") == nil)
        #expect(LanguagePair(traveler: "zh", local: "en").applyingDetectedLocal("zh-Hant") == nil)
        #expect(LanguagePair(traveler: "EN", local: "fr").applyingDetectedLocal("en") == nil)
    }

    @Test("A GPS fix abroad replaces their language and keeps yours")
    func abroadIsApplied() {
        let pair = LanguagePair(traveler: "en", local: "es")
        #expect(pair.applyingDetectedLocal("ja") == LanguagePair(traveler: "en", local: "ja"))
    }

    @Test("A GPS fix matching the current destination changes nothing")
    func unchangedDestinationIsIgnored() {
        #expect(LanguagePair(traveler: "en", local: "fr").applyingDetectedLocal("fr") == nil)
        #expect(LanguagePair(traveler: "en", local: "fr").applyingDetectedLocal("") == nil)
    }

    @Test("The default destination is Spanish, or English for a Spanish speaker")
    func defaultDestination() {
        #expect(LanguagePair.defaultLocal(forTraveler: "en") == "es")
        #expect(LanguagePair.defaultLocal(forTraveler: "ja") == "es")
        #expect(LanguagePair.defaultLocal(forTraveler: "es") == "en")
        #expect(LanguagePair.defaultLocal(forTraveler: "es-MX") == "en")
    }

    @Test("A stored destination survives unless it collides with your language")
    func storedDestination() {
        #expect(LanguagePair.local(stored: "ja", traveler: "en") == "ja")
        #expect(LanguagePair.local(stored: nil, traveler: "en") == "es")
        #expect(LanguagePair.local(stored: "", traveler: "en") == "es")
        #expect(LanguagePair.local(stored: "en", traveler: "en") == "es")
        #expect(LanguagePair.local(stored: "es", traveler: "es") == "en")
    }

    @Test("No resolved default ever equals the traveler's language")
    func defaultNeverCollides() {
        for traveler in SupportedLanguages.codes {
            for stored in [nil, traveler] + SupportedLanguages.codes.map(Optional.some) {
                let local = LanguagePair.local(stored: stored, traveler: traveler)
                #expect(!LanguagePair.sameLanguage(local, traveler), "\(traveler) resolved to \(local)")
            }
        }
    }

    @Test("Choosing your own language as theirs swaps the sides")
    func choosingLocalSwapsOnCollision() {
        let pair = LanguagePair(traveler: "en", local: "ja")
        #expect(pair.choosingLocal("en") == LanguagePair(traveler: "ja", local: "en"))
        #expect(pair.choosingLocal("fr") == LanguagePair(traveler: "en", local: "fr"))
    }

    @Test("Choosing their language as yours swaps the sides")
    func choosingTravelerSwapsOnCollision() {
        let pair = LanguagePair(traveler: "en", local: "ja")
        #expect(pair.choosingTraveler("ja") == LanguagePair(traveler: "ja", local: "en"))
        #expect(pair.choosingTraveler("de") == LanguagePair(traveler: "de", local: "ja"))
    }

    @Test("Swapping twice restores the pair")
    func swapRoundTrips() {
        let pair = LanguagePair(traveler: "ko", local: "th")
        #expect(pair.swapped == LanguagePair(traveler: "th", local: "ko"))
        #expect(pair.swapped.swapped == pair)
    }
}

@Suite("Supported languages")
struct SupportedLanguagesTests {
    @Test("The travel-popularity order covers exactly the supported languages")
    func popularityCoversSupported() {
        #expect(SupportedLanguages.byTravelPopularity.count == 22)
        #expect(Set(SupportedLanguages.byTravelPopularity) == Set(SupportedLanguages.codes))
    }

    @Test("Destinations leave out the traveler's own language and keep the order")
    func destinationsExcludeTraveler() {
        let destinations = SupportedLanguages.destinations(forTraveler: "en")
        #expect(destinations.count == 21)
        #expect(!destinations.contains("en"))
        #expect(Array(destinations.prefix(4)) == ["es", "fr", "it", "ja"])
        #expect(!SupportedLanguages.destinations(forTraveler: "zh-Hant").contains("zh"))
    }

    @Test("Anyone who doesn't speak English is offered English first")
    func englishLeadsForEveryoneElse() {
        for traveler in SupportedLanguages.codes where traveler != "en" {
            #expect(SupportedLanguages.destinations(forTraveler: traveler).first == "en", "\(traveler)")
        }
    }

    @Test("A Spanish speaker's default destination heads their picker")
    func spanishDefaultLeadsPicker() {
        #expect(SupportedLanguages.destinations(forTraveler: "es").first == LanguagePair.defaultLocal(forTraveler: "es"))
    }

    @Test("An unsupported traveler language is offered every destination")
    func unsupportedTravelerSeesAll() {
        #expect(SupportedLanguages.destinations(forTraveler: "da") == SupportedLanguages.byTravelPopularity)
    }
}

@Suite("First-run stage")
struct FirstRunStageTests {
    @Test("A fresh install starts at the destination picker")
    func freshInstall() {
        #expect(FirstRunStage.resolve(stored: nil, completedTurns: 0) == .chooseDestination)
        #expect(FirstRunStage.resolve(stored: nil, completedTurns: 0).offersDestination)
    }

    @Test("An existing user who already translated never sees the walkthrough")
    func existingUserSkips() {
        #expect(FirstRunStage.resolve(stored: nil, completedTurns: 1) == .done)
        #expect(FirstRunStage.resolve(stored: "garbage", completedTurns: 3) == .done)
    }

    @Test("A stored stage wins over the turn count")
    func storedStageWins() {
        #expect(FirstRunStage.resolve(stored: "holdTheirs", completedTurns: 1) == .holdTheirs)
        #expect(FirstRunStage.resolve(stored: "done", completedTurns: 0) == .done)
    }

    @Test("Picking or skipping the destination starts the coach")
    func destinationLeadsToCoach() {
        #expect(FirstRunStage.chooseDestination.afterDestination == .holdYours)
        #expect(FirstRunStage.done.afterDestination == .done)
        #expect(FirstRunStage.holdTheirs.afterDestination == .holdTheirs)
    }

    @Test("Your turn invites theirs, and their turn completes the walkthrough")
    func coachSequence() {
        #expect(FirstRunStage.holdYours.after(turnBy: .traveler) == .holdTheirs)
        #expect(FirstRunStage.holdTheirs.after(turnBy: .local) == .done)
    }

    @Test("A turn out of order does not skip a coaching step")
    func outOfOrderTurns() {
        #expect(FirstRunStage.holdYours.after(turnBy: .local) == .holdYours)
        #expect(FirstRunStage.holdTheirs.after(turnBy: .traveler) == .holdTheirs)
        #expect(FirstRunStage.done.after(turnBy: .traveler) == .done)
        #expect(FirstRunStage.chooseDestination.after(turnBy: .traveler) == .chooseDestination)
    }

    @Test("The coach points at the button for the step")
    func beckoning() {
        #expect(FirstRunStage.holdYours.beckoning == .traveler)
        #expect(FirstRunStage.holdTheirs.beckoning == .local)
        #expect(FirstRunStage.chooseDestination.beckoning == nil)
        #expect(FirstRunStage.done.beckoning == nil)
    }
}
