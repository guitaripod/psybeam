import Combine
import Foundation
import PsybeamKit

@MainActor
final class ConversationViewModel {
    let travelerLeg: TranslationLeg
    let localLeg: TranslationLeg

    let languagePublisher = PassthroughSubject<LanguagePair, Never>()
    let activeSidePublisher = PassthroughSubject<Side?, Never>()
    let amplitudePublisher = PassthroughSubject<Float, Never>()

    private(set) var pair: LanguagePair
    private var languageLocked = false
    private var activeSide: Side?
    private var cancellables = Set<AnyCancellable>()

    private var warmUpArmed = false
    private var warmedUp = false
    private var languageResolved = false
    private var warmUpFallback: Task<Void, Never>?

    init(travelerCall: RealtimeCallService, localCall: RealtimeCallService) {
        let pair = LanguagePair(traveler: AppSettings.travelerLanguage, local: AppSettings.localLanguage)
        self.pair = pair
        self.travelerLeg = TranslationLeg(call: travelerCall, speaker: .traveler, pair: pair)
        self.localLeg = TranslationLeg(call: localCall, speaker: .local, pair: pair)
        wireAmplitude()
    }

    func start() {
        languagePublisher.send(pair)
    }

    /// Warm-connect both legs so the first hold-to-talk is instant. When GPS
    /// auto-detect is on, the local language is about to change from the stored
    /// value to the detected one; connecting now would mint a session in the
    /// wrong language and tear it straight down on the GPS result — wasting a
    /// mint and (before the server reservation sweep) leaking the up-front
    /// charge. So the first warm-up waits for the first GPS resolution, or a
    /// short fallback when no location ever arrives (denied/restricted/no fix),
    /// then connects with the language that will actually be used.
    func warmUp() {
        warmUpArmed = true
        if warmedUp || languageIsSettled {
            performWarmUp()
        } else {
            scheduleWarmUpFallback()
        }
    }

    private var languageIsSettled: Bool {
        !AppSettings.autoDetectLocation || languageLocked || languageResolved
    }

    private func scheduleWarmUpFallback() {
        guard warmUpFallback == nil else { return }
        warmUpFallback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled else { return }
            self.warmUpFallback = nil
            if self.warmUpArmed, !self.warmedUp { self.performWarmUp() }
        }
    }

    private func performWarmUp() {
        warmedUp = true
        warmUpFallback?.cancel()
        warmUpFallback = nil
        travelerLeg.warmUp()
        localLeg.warmUp()
    }

    func end() {
        warmUpArmed = false
        warmUpFallback?.cancel()
        warmUpFallback = nil
        travelerLeg.end()
        localLeg.end()
        activeSide = nil
        activeSidePublisher.send(nil)
    }

    func holdDown(_ speaker: Side) {
        let leg = speaker == .traveler ? travelerLeg : localLeg
        let other = speaker == .traveler ? localLeg : travelerLeg
        if other.isHolding { other.holdUp() }
        leg.holdDown()
        activeSide = speaker
        activeSidePublisher.send(speaker)
    }

    func holdUp(_ speaker: Side) {
        let leg = speaker == .traveler ? travelerLeg : localLeg
        leg.holdUp()
        if activeSide == speaker {
            activeSide = nil
            activeSidePublisher.send(nil)
        }
    }

    func setLocalLanguage(_ code: String) {
        languageLocked = true
        apply(pair.choosingLocal(code))
    }

    func setTravelerLanguage(_ code: String) {
        languageLocked = true
        apply(pair.choosingTraveler(code))
    }

    func swapLanguages() {
        languageLocked = true
        apply(pair.swapped)
    }

    #if DEBUG
    /// Shows a demo's pair everywhere the view model is read, Settings
    /// included, without storing it or letting GPS replace it.
    func showDemoPair(_ demoPair: LanguagePair) {
        languageLocked = true
        pair = demoPair
        updateLegs()
    }
    #endif

    /// A GPS fix counts toward settling the language even when it is ignored
    /// for resolving to your own language: being at home is a real answer, and
    /// warm-up should stop waiting for one.
    func applyDetectedLanguage(_ code: String) {
        guard AppSettings.autoDetectLocation, !languageLocked else { return }
        languageResolved = true
        if let detected = pair.applyingDetectedLocal(code) { apply(detected) }
        if warmUpArmed, !warmedUp { performWarmUp() }
    }

    /// Their language is stored on every change, even when only yours moved:
    /// an unstored one is derived from yours, so a later change to yours, or a
    /// repaired same-language pair, would otherwise come back as a different
    /// destination on the next launch. Yours is stored only once it changes, so
    /// it keeps following the device language until you choose one.
    private func apply(_ next: LanguagePair) {
        guard next != pair else { return }
        if next.traveler != pair.traveler { AppSettings.travelerLanguage = next.traveler }
        AppSettings.localLanguage = next.local
        pair = next
        updateLegs()
        languagePublisher.send(pair)
    }

    private func updateLegs() {
        travelerLeg.setPair(pair)
        localLeg.setPair(pair)
    }

    private func wireAmplitude() {
        travelerLeg.amplitudePublisher
            .sink { [weak self] level in if self?.activeSide == .traveler { self?.amplitudePublisher.send(level) } }
            .store(in: &cancellables)
        localLeg.amplitudePublisher
            .sink { [weak self] level in if self?.activeSide == .local { self?.amplitudePublisher.send(level) } }
            .store(in: &cancellables)
    }
}
