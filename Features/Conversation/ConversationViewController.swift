import AVFAudio
import Combine
import PsybeamCore
import SwiftUI
import UIKit
import AICreditsUI
import MidgarCore

final class ConversationViewController: UIViewController {
    let viewModel: ConversationViewModel
    let location = LocationLanguageService()
    var cancellables = Set<AnyCancellable>()

    let visualizer = WaveVisualizerView()
    let convoRoot = UIView()
    let statusLabel = UILabel()
    let promptLabel = UILabel()
    let translatedLabel = UILabel()
    let sourceLabel = UILabel()
    let coachLabel = UILabel()
    let consentButton = UIButton(type: .system)
    /// Lifts the "not now" explanation until its button clears the cloud badge
    /// and the talk buttons, as it must at the largest text sizes on small
    /// screens. Active only while the button shows, so a hidden button never
    /// pushes a caption up.
    lazy var consentButtonClearance = consentButton.bottomAnchor.constraint(
        lessThanOrEqualTo: cloudBadge.topAnchor, constant: -12)
    let micSettingsButton = UIButton(type: .system)
    lazy var micSettingsButtonClearance = micSettingsButton.bottomAnchor.constraint(
        lessThanOrEqualTo: cloudBadge.topAnchor, constant: -12)
    let noticeButton = UIButton(type: .system)
    let cloudBadge = UILabel()
    let gearGlass = UIVisualEffectView()
    let gearIcon = UIImageView()
    let languageBarHost = UIView()
    let youLangButton = UIButton(type: .system)
    let themLangButton = UIButton(type: .system)
    let swapButton = UIButton(type: .system)
    let buttonRow = UIStackView()
    let captionColumn = UILayoutGuide()
    let controlColumn = UILayoutGuide()
    var appliedPlan: ConversationLayoutPlan?
    var plannedSize = CGSize.zero
    lazy var captionCenter = makeCaptionCenter()
    lazy var promptCenter = promptLabel.centerYAnchor.constraint(equalTo: convoRoot.centerYAnchor, constant: -158)
    lazy var buttonRowHeight = buttonRow.heightAnchor.constraint(equalToConstant: ConversationLayoutPlan.defaultButtonHeight)
    lazy var languageBarCenterX = makeLanguageBarCenterX()
    lazy var captionColumnConstraints = (
        captionColumn.leftAnchor.constraint(equalTo: convoRoot.leftAnchor),
        captionColumn.rightAnchor.constraint(equalTo: convoRoot.leftAnchor))
    lazy var controlColumnConstraints = (
        controlColumn.leftAnchor.constraint(equalTo: convoRoot.leftAnchor),
        controlColumn.rightAnchor.constraint(equalTo: convoRoot.leftAnchor))
    lazy var stackedRowBottom = buttonRow.bottomAnchor.constraint(equalTo: convoRoot.safeAreaLayoutGuide.bottomAnchor, constant: -24)
    lazy var stackedBadgeBottom = cloudBadge.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -10)
    lazy var stackedCoachBottom = coachLabel.bottomAnchor.constraint(equalTo: cloudBadge.topAnchor, constant: -16)
    lazy var sideBadgeBottom = cloudBadge.bottomAnchor.constraint(equalTo: convoRoot.safeAreaLayoutGuide.bottomAnchor, constant: -10)
    lazy var sideRowBottom = buttonRow.bottomAnchor.constraint(equalTo: cloudBadge.topAnchor, constant: -10)
    lazy var sideCoachBottom = coachLabel.bottomAnchor.constraint(equalTo: convoRoot.safeAreaLayoutGuide.bottomAnchor, constant: -24)

    let travelerAccent = UIColor(red: 0.34, green: 0.74, blue: 1.0, alpha: 1)
    let localAccent = UIColor(red: 0.42, green: 1.0, blue: 0.72, alpha: 1)
    let errorRed = UIColor(red: 1.0, green: 0.32, blue: 0.36, alpha: 1)
    let amber = UIColor(red: 1.0, green: 0.66, blue: 0.22, alpha: 1)
    let brand = UIColor(red: 0.30, green: 0.62, blue: 1.0, alpha: 1)
    lazy var meButton = TalkButton(accent: travelerAccent, hint: String(localized: "HOLD · YOU"), micSymbol: "mic.fill")
    lazy var themButton = TalkButton(accent: localAccent, hint: String(localized: "HOLD · THEM"), micSymbol: "person.wave.2.fill")

    let impact = UIImpactFeedbackGenerator(style: .medium)
    let release = UIImpactFeedbackGenerator(style: .soft)
    let notify = UINotificationFeedbackGenerator()
    let earcon = Earcon()
    var savedBrightness: CGFloat?
    var travelerText = ""
    var localText = ""
    var displayAudience: Side = .traveler
    var translationAudience: Side = .traveler
    var hasTranslation = false
    var turnProducedText = false
    var heldSide: Side?
    var pendingTurns: Set<Side> = []
    var needsConsentOnAppear = false
    var needsDestinationOnAppear = false
    var sessionStarted = false
    var micDenied = false
    var knownBalance: Int?
    var shownNotice: SessionNotice?
    var displayedPair: LanguagePair
    var firstRun = AppSettings.firstRunStage
    #if DEBUG
    var demo: DemoConfiguration?
    var demoPlayer: DemoScriptPlayer?
    #endif

    init(viewModel: ConversationViewModel) {
        self.viewModel = viewModel
        self.displayedPair = viewModel.pair
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyMaxBrightness()
        primeHaptics()
        if needsConsentOnAppear {
            needsConsentOnAppear = false
            presentConsent()
        } else if needsDestinationOnAppear {
            needsDestinationOnAppear = false
            presentDestinationPicker()
        }
        #if DEBUG
        startDemoScriptIfNeeded()
        startDebugPressIfNeeded()
        #endif
    }

    func primeHaptics() {
        impact.prepare()
        release.prepare()
        notify.prepare()
    }

    func applyMaxBrightness() {
        guard AppSettings.keepScreenBright else {
            restoreBrightness()
            return
        }
        let screen = view.window?.windowScene?.screen
        if savedBrightness == nil { savedBrightness = screen?.brightness }
        screen?.brightness = 1.0
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func restoreBrightness() {
        if let savedBrightness {
            view.window?.windowScene?.screen.brightness = savedBrightness
            self.savedBrightness = nil
        }
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// With consent already given, the session starts now, unless the
    /// destination picker is still owed: then it starts once a destination is
    /// set, so warm-up never mints a session in a language about to change.
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        layoutVisualizer()
        layoutConvo()
        bind()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: ConversationViewController, _) in
            self.refreshResting()
        }
        if applyPreviewIfNeeded() { return }
        convoRoot.alpha = 1
        updateLanguages(viewModel.pair)
        if !AppSettings.aiConsentGranted {
            needsConsentOnAppear = true
        } else if firstRun.offersDestination {
            needsDestinationOnAppear = true
        } else {
            startSession()
        }
    }

    var isDemo: Bool {
        #if DEBUG
        demo != nil
        #else
        false
        #endif
    }

    var needsConsent: Bool {
        !AppSettings.aiConsentGranted && !isDemo
    }

    func bind() {
        viewModel.travelerLeg.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.render(legState: state, speaker: .traveler) }
            .store(in: &cancellables)
        viewModel.localLeg.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.render(legState: state, speaker: .local) }
            .store(in: &cancellables)
        viewModel.travelerLeg.textPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in self?.handleText(text, speaker: .traveler) }
            .store(in: &cancellables)
        viewModel.localLeg.textPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in self?.handleText(text, speaker: .local) }
            .store(in: &cancellables)
        viewModel.travelerLeg.sourcePublisher
            .merge(with: viewModel.localLeg.sourcePublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in self?.sourceLabel.text = source }
            .store(in: &cancellables)
        viewModel.travelerLeg.finishedPublisher.map { Side.traveler }
            .merge(with: viewModel.localLeg.finishedPublisher.map { Side.local })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speaker in self?.onTurnFinished(speaker) }
            .store(in: &cancellables)
        viewModel.languagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pair in self?.updateLanguages(pair) }
            .store(in: &cancellables)
        viewModel.amplitudePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in self?.visualizer.setLevel(level) }
            .store(in: &cancellables)
        location.detected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self, !self.isDemo else { return }
                self.viewModel.applyDetectedLanguage(result.language)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.viewModel.end()
                self?.abandonPendingTurns()
                self?.restoreBrightness()
                self?.visualizer.setPaused(true)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.visualizer.setPaused(false)
                self.applyMaxBrightness()
                self.primeHaptics()
                self.recheckMicPermission()
                if AppSettings.aiConsentGranted, self.sessionStarted {
                    self.warmUpIfMicGranted()
                    self.refreshBalance()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NetworkMonitor.didChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.connectivityChanged() }
            .store(in: &cancellables)
        AICreditsManager.store.$balance
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] balance in
                guard let self, self.knownBalance != nil else { return }
                self.knownBalance = balance
                self.refreshNotice()
            }
            .store(in: &cancellables)
    }

    func render(legState state: TranslationState, speaker: Side) {
        switch state {
        case .armed:
            visualizer.apply(speaker == .traveler ? .listening : .speaking)
            setStatus(String(localized: "GET READY"), color: speaker == .traveler ? travelerAccent : localAccent)
        case .listening:
            visualizer.apply(speaker == .traveler ? .listening : .speaking)
            setStatus(String(localized: "LISTENING"), color: speaker == .traveler ? travelerAccent : localAccent)
            if speaker == .local, AppSettings.turnChime {
                earcon.play()
                visualizer.bloom()
            }
        case .processing:
            visualizer.apply(.processing)
            setStatus(String(localized: "CONNECTING"), color: amber)
        case .reconnecting:
            visualizer.apply(.processing)
            setStatus(String(localized: "RECONNECTING"), color: amber)
        case .quotaExhausted:
            visualizer.apply(.error)
            setStatus(String(localized: "OUT OF MINUTES"), color: errorRed)
            knownBalance = 0
            refreshNotice()
            presentStoreIfPossible()
        case .offline:
            visualizer.apply(.error)
            setStatus(String(localized: "NO CONNECTION"), color: errorRed)
        case .permissionDenied:
            visualizer.apply(.error)
            micDenied = true
            setStatus("", color: .clear)
            refreshResting()
        case .error(.unsupportedLanguage):
            visualizer.apply(.error)
            setStatus(String(localized: "LANGUAGE NOT SUPPORTED"), color: errorRed)
        case .error:
            visualizer.apply(.error)
            setStatus(String(localized: "HOLD TO RETRY"), color: errorRed)
        case .idle:
            visualizer.apply(.idle)
            setStatus("", color: .clear)
        default:
            break
        }
    }

    func setStatus(_ text: String, color: UIColor) {
        UIView.transition(with: statusLabel, duration: 0.2, options: .transitionCrossDissolve) {
            self.statusLabel.text = text
            self.statusLabel.textColor = color
        }
    }

    /// While a turn is opening, `text` arrives empty — that's the cue to invite the
    /// upcoming speaker in *their own* language (in `promptLabel`) while the prior
    /// turn stays readable, only ghosted, so you can re-read their reply as you
    /// reach to answer. The first real delta restores the caption and hides the
    /// prompt. The prompt language is the *recorded* language, not the device locale.
    func handleText(_ text: String, speaker: Side) {
        if speaker == .traveler { travelerText = text } else { localText = text }
        let spokenLanguage = speaker == .traveler ? displayedPair.traveler : displayedPair.local
        let audience: Side = text.isEmpty ? speaker : speaker.other
        setAudience(audience)
        if text.isEmpty {
            promptLabel.text = Self.speakPrompt(for: spokenLanguage)
            promptLabel.textColor = speaker == .traveler ? travelerAccent : localAccent
            UIView.animate(withDuration: 0.25) {
                self.promptLabel.alpha = 1
                self.translatedLabel.alpha = 0
            }
        } else {
            hasTranslation = true
            turnProducedText = true
            translationAudience = audience
            translatedLabel.font = captionFont
            translatedLabel.textAlignment = .center
            translatedLabel.text = text
            translatedLabel.textColor = .white
            UIView.animate(withDuration: 0.2) {
                self.promptLabel.alpha = 0
                self.translatedLabel.alpha = 1
            }
        }
    }

    var captionFont: UIFont {
        .systemFont(ofSize: appliedPlan?.captionPointSize ?? ConversationLayoutPlan.phoneCaptionPointSize, weight: .bold)
    }

    func startSession() {
        sessionStarted = true
        micDenied = AVAudioApplication.shared.recordPermission == .denied
        location.startIfAuthorized()
        if !location.isAuthorized { viewModel.stopWaitingForLocation() }
        viewModel.start()
        warmUpIfMicGranted()
        refreshBalance()
        refreshNotice()
        refreshResting()
    }

    /// Warming up opens the audio path, which on a first run would raise the
    /// microphone prompt before the user has pressed anything. So the warm-up
    /// waits until the permission is granted, whether that is already so or
    /// the user's first hold has just granted it.
    func warmUpIfMicGranted() {
        guard AVAudioApplication.shared.recordPermission == .granted else { return }
        viewModel.warmUp()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyLayoutPlan()
    }

    static let promptAboveCaption: CGFloat = 118

    /// Returns whether the hold started. A press without consent re-presents
    /// the consent sheet, the first press asks for the microphone, and one with
    /// the microphone denied shows how to fix it; none of them lights the
    /// button, since nothing is listening.
    func pressBegan(_ speaker: Side) -> Bool {
        guard AppSettings.aiConsentGranted else {
            presentConsent()
            return false
        }
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            render(legState: .permissionDenied(.microphone), speaker: speaker)
            return false
        case .undetermined:
            requestMicPermission()
            return false
        default:
            break
        }
        impact.impactOccurred()
        release.prepare()
        beginHold(speaker)
        viewModel.holdDown(speaker)
        return true
    }

    func pressEnded(_ speaker: Side) {
        release.impactOccurred()
        impact.prepare()
        viewModel.holdUp(speaker)
        endHold()
    }

    /// Screen-side bookkeeping for a hold, shared by live holds and scripted
    /// demo holds so both drive the same coach and caption state.
    func beginHold(_ speaker: Side) {
        heldSide = speaker
        turnProducedText = false
        pendingTurns.insert(speaker)
        refreshCoach()
    }

    func endHold() {
        let speaker = heldSide
        heldSide = nil
        if turnProducedText {
            refreshCoach()
        } else {
            if let speaker { pendingTurns.remove(speaker) }
            restoreResting()
        }
    }

    /// Ending the session cancels a released turn's settle, so a turn still
    /// settling will never report finished. Forgetting it keeps the coach from
    /// waiting on it forever.
    func abandonPendingTurns() {
        pendingTurns.removeAll()
        refreshCoach()
    }

    /// The closing delta of a turn — give it a body: a success tap and a small
    /// settle so the caption reads as committed, not merely paused mid-stream.
    func onTurnFinished(_ speaker: Side) {
        notify.notificationOccurred(.success)
        notify.prepare()
        if !isDemo { ReviewPrompt.recordSuccess(in: view.window?.windowScene) }
        pendingTurns.remove(speaker)
        let before = firstRun
        setFirstRun(firstRun.after(turnBy: speaker))
        refreshCoach()
        if before != .done, firstRun == .done { scheduleLocationOffer() }
        let base = translatedLabel.transform
        UIView.animate(withDuration: 0.14, animations: {
            self.translatedLabel.transform = base.scaledBy(x: 1.035, y: 1.035)
        }, completion: { _ in
            UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.4) {
                self.translatedLabel.transform = base
            }
        })
    }

    /// Settings can withdraw consent or change either language, so the resting
    /// state is recomputed when it closes; a changed pair ends the coach just
    /// as it does from the language bar.
    @objc func openSettings() {
        impact.impactOccurred()
        visualizer.setPaused(true)
        let settings = SettingsViewController(
            viewModel: viewModel,
            onBrightnessChanged: { [weak self] in self?.applyMaxBrightness() },
            onAutoDetectEnabled: { [weak self] in self?.location.requestAuthorization() }
        )
        let pairBeforeSettings = viewModel.pair
        settings.onDismiss = { [weak self] in
            guard let self else { return }
            self.visualizer.setPaused(false)
            if self.viewModel.pair != pairBeforeSettings { self.setFirstRun(.done) }
            self.refreshResting()
        }
        if let sheet = settings.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(settings, animated: true)
    }

    /// Orientation always follows the audience of the current text: your speech
    /// (in their language) faces them; their reply (in your language) faces you.
    func applyFlip(animated: Bool) {
        let transform: CGAffineTransform = displayAudience == .local ? CGAffineTransform(rotationAngle: .pi) : .identity
        let apply = {
            self.translatedLabel.transform = transform
            self.promptLabel.transform = transform
        }
        if animated {
            UIView.animate(withDuration: 0.45, delay: 0, options: .curveEaseInOut, animations: apply)
        } else {
            apply()
        }
    }

    func setAudience(_ audience: Side) {
        guard displayAudience != audience else { return }
        displayAudience = audience
        applyFlip(animated: true)
    }

    func updateLanguages(_ pair: LanguagePair) {
        displayedPair = pair
        meButton.languageLabel.text = LanguageNames.endonym(pair.traveler)
        themButton.languageLabel.text = LanguageNames.endonym(pair.local)
        meButton.accessibilityLabel = String(localized: "Hold to speak \(LanguageNames.endonym(pair.traveler))")
        themButton.accessibilityLabel = String(localized: "Hold while they speak \(LanguageNames.endonym(pair.local))")
        setLangButtonTitle(youLangButton, LanguageNames.endonym(pair.traveler), travelerAccent)
        setLangButtonTitle(themLangButton, LanguageNames.endonym(pair.local), localAccent)
        youLangButton.menu = makeLangMenu(isTraveler: true)
        themLangButton.menu = makeLangMenu(isTraveler: false)
        refreshResting()
    }

    func pin(_ subview: UIView) {
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: view.topAnchor),
            subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    /// Opens the consent sheet while consent is missing; otherwise taps are
    /// inert, so this never competes with the hold-to-talk buttons.
    @objc func handleScreenTap() {
        if needsConsent { presentConsent() }
    }

    static func speakPrompt(for code: String) -> String {
        let base = String(code.prefix(2)).lowercased()
        return prompts[base] ?? "Speak now"
    }

    static let prompts: [String: String] = [
        "en": "Speak now", "es": "Hable ahora", "fr": "Parlez maintenant",
        "de": "Sprechen Sie jetzt", "it": "Parli pure", "pt": "Pode falar",
        "nl": "Spreek nu", "ru": "Говорите", "ar": "تكلم الآن",
        "tr": "Şimdi konuşun", "el": "Μιλήστε τώρα", "hi": "अब बोलिए",
        "ja": "話してください", "ko": "말씀하세요", "zh": "请说话",
        "th": "พูดได้เลย", "vi": "Hãy nói", "pl": "Mów teraz",
        "sv": "Tala nu", "id": "Silakan bicara", "uk": "Говоріть",
        "he": "דבר עכשיו", "fi": "Puhu nyt",
    ]
}
