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

    func warmUp() {
        travelerLeg.warmUp()
        localLeg.warmUp()
    }

    func end() {
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
        applyLocal(code)
    }

    func setTravelerLanguage(_ code: String) {
        guard code != pair.traveler else { return }
        pair = LanguagePair(traveler: code, local: pair.local)
        AppSettings.travelerLanguage = code
        updateLegs()
        languagePublisher.send(pair)
    }

    func swapLanguages() {
        guard pair.traveler != pair.local else { return }
        pair = LanguagePair(traveler: pair.local, local: pair.traveler)
        AppSettings.travelerLanguage = pair.traveler
        AppSettings.localLanguage = pair.local
        languageLocked = true
        updateLegs()
        languagePublisher.send(pair)
    }

    func applyDetectedLanguage(_ code: String) {
        guard AppSettings.autoDetectLocation, !languageLocked else { return }
        applyLocal(code)
    }

    private func applyLocal(_ code: String) {
        guard code != pair.local else { return }
        pair = LanguagePair(traveler: pair.traveler, local: code)
        AppSettings.localLanguage = code
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
