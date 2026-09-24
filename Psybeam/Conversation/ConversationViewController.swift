import AVFAudio
import Combine
import PsybeamKit
import SwiftUI
import UIKit
import AICreditsUI

final class ConversationViewController: UIViewController {
    private let viewModel: ConversationViewModel
    private let location = LocationLanguageService()
    private var cancellables = Set<AnyCancellable>()

    private let visualizer = WaveVisualizerView()
    private let convoRoot = UIView()
    private let statusLabel = UILabel()
    private let promptLabel = UILabel()
    private let translatedLabel = UILabel()
    private let sourceLabel = UILabel()
    private let coachLabel = UILabel()
    private let consentButton = UIButton(type: .system)
    /// Lifts the "not now" explanation until its button clears the cloud badge
    /// and the talk buttons, as it must at the largest text sizes on small
    /// screens. Active only while the button shows, so a hidden button never
    /// pushes a caption up.
    private lazy var consentButtonClearance = consentButton.bottomAnchor.constraint(
        lessThanOrEqualTo: cloudBadge.topAnchor, constant: -12)
    private let cloudBadge = UILabel()
    private let gearGlass = UIVisualEffectView()
    private let gearIcon = UIImageView()
    private let languageBarHost = UIView()
    private let youLangButton = UIButton(type: .system)
    private let themLangButton = UIButton(type: .system)
    private let swapButton = UIButton(type: .system)

    private let travelerAccent = UIColor(red: 0.34, green: 0.74, blue: 1.0, alpha: 1)
    private let localAccent = UIColor(red: 0.42, green: 1.0, blue: 0.72, alpha: 1)
    private let errorRed = UIColor(red: 1.0, green: 0.32, blue: 0.36, alpha: 1)
    private let amber = UIColor(red: 1.0, green: 0.66, blue: 0.22, alpha: 1)
    private let brand = UIColor(red: 0.30, green: 0.62, blue: 1.0, alpha: 1)
    private lazy var meButton = TalkButton(accent: travelerAccent, hint: String(localized: "HOLD · YOU"), micSymbol: "mic.fill")
    private lazy var themButton = TalkButton(accent: localAccent, hint: String(localized: "HOLD · THEM"), micSymbol: "person.wave.2.fill")

    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let release = UIImpactFeedbackGenerator(style: .soft)
    private let notify = UINotificationFeedbackGenerator()
    private let earcon = Earcon()
    private var savedBrightness: CGFloat?
    private var travelerText = ""
    private var localText = ""
    private var displayAudience: Side = .traveler
    private var translationAudience: Side = .traveler
    private var hasTranslation = false
    private var turnProducedText = false
    private var heldSide: Side?
    private var pendingTurns: Set<Side> = []
    private var needsConsentOnAppear = false
    private var needsDestinationOnAppear = false
    private var sessionStarted = false
    private var micDenied = false
    private var displayedPair: LanguagePair
    private var firstRun = AppSettings.firstRunStage
    #if DEBUG
    private var demo: DemoConfiguration?
    private var demoPlayer: DemoScriptPlayer?
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
        #endif
    }

    private func primeHaptics() {
        impact.prepare()
        release.prepare()
        notify.prepare()
    }

    private func applyMaxBrightness() {
        guard AppSettings.keepScreenBright else {
            restoreBrightness()
            return
        }
        let screen = view.window?.windowScene?.screen
        if savedBrightness == nil { savedBrightness = screen?.brightness }
        screen?.brightness = 1.0
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func restoreBrightness() {
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

    private var isDemo: Bool {
        #if DEBUG
        demo != nil
        #else
        false
        #endif
    }

    private var needsConsent: Bool {
        !AppSettings.aiConsentGranted && !isDemo
    }

    /// DEBUG-only screenshot and recording modes, selected by `PSYBEAM_DEMO`
    /// and documented in `marketing/video/README.md`. Every mode renders
    /// through the production paths and persists nothing.
    @discardableResult
    private func applyPreviewIfNeeded() -> Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let uiLanguage = Bundle.main.preferredLocalizations.first ?? "en"
        guard let demo = DemoConfiguration(environment: environment, uiLanguage: uiLanguage) else { return false }
        self.demo = demo
        convoRoot.alpha = 1
        firstRun = demo.initialStage
        viewModel.showDemoPair(demo.phrasebook.pair)
        updateLanguages(demo.phrasebook.pair)
        switch demo.mode {
        case "listening":
            showDemoTurn(line: 0, finished: false)
        case "them":
            showDemoTurn(line: 1, finished: false)
        case "coach-theirs":
            showDemoTurn(line: 0, finished: true)
        default:
            refreshResting()
        }
        visualizer.setLevel(demo.level ?? (["listening", "them", "settings", "consent"].contains(demo.mode) ? 0.6 : 0))
        let mode = demo.mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.presentDemoSheet(for: mode) }
        return true
        #else
        return false
        #endif
    }

    private func bind() {
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
                if AppSettings.aiConsentGranted, self.sessionStarted { self.viewModel.warmUp() }
            }
            .store(in: &cancellables)
    }

    private func render(legState state: TranslationState, speaker: Side) {
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
            presentStoreIfPossible()
        case .offline:
            visualizer.apply(.error)
            setStatus(String(localized: "NO CONNECTION"), color: errorRed)
        case .permissionDenied:
            visualizer.apply(.error)
            micDenied = true
            setStatus(String(localized: "TAP TO ENABLE MIC"), color: errorRed)
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

    private func setStatus(_ text: String, color: UIColor) {
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
    private func handleText(_ text: String, speaker: Side) {
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
            translatedLabel.font = Self.captionFont
            translatedLabel.textAlignment = .center
            translatedLabel.text = text
            translatedLabel.textColor = .white
            UIView.animate(withDuration: 0.2) {
                self.promptLabel.alpha = 0
                self.translatedLabel.alpha = 1
            }
        }
    }

    private static let captionFont = UIFont.systemFont(ofSize: 36, weight: .bold)

    private func startSession() {
        sessionStarted = true
        requestMicPermission()
        location.start()
        viewModel.start()
        viewModel.warmUp()
    }

    /// On a 402 from /start (out of credits) the leg surfaces `.quotaExhausted`;
    /// present the credit store so the user can top up minutes.
    private func presentStoreIfPossible() {
        guard presentedViewController == nil else { return }
        let store = AICreditsManager.store
        let host = UIHostingController(rootView: CreditStoreView().environmentObject(store))
        Task { await store.loadCatalog() }
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(host, animated: true)
    }

    private func presentConsent() {
        guard presentedViewController == nil else { return }
        let consent = ConsentViewController()
        consent.isModalInPresentation = true
        consent.onAgree = { [weak self] in
            guard let self else { return }
            guard !self.isDemo else {
                self.dismiss(animated: true)
                return
            }
            AppSettings.aiConsentGranted = true
            self.dismiss(animated: true) { self.continueAfterConsent() }
        }
        consent.onDecline = { [weak self] in
            self?.dismiss(animated: true) { self?.refreshResting() }
        }
        if let sheet = consent.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }
        present(consent, animated: true)
    }

    private func continueAfterConsent() {
        refreshResting()
        if firstRun.offersDestination {
            presentDestinationPicker()
        } else {
            startSession()
        }
    }

    /// Shown once, after consent, to a user who has never finished a
    /// translation. If something else is on screen the session starts anyway
    /// and the picker waits for the next launch, so first run never stalls.
    private func presentDestinationPicker() {
        guard presentedViewController == nil else {
            if !isDemo { startSession() }
            return
        }
        let picker = DestinationPickerViewController(
            destinations: SupportedLanguages.destinations(forTraveler: displayedPair.traveler))
        picker.onPick = { [weak self] code in self?.finishDestination(choosing: code) }
        picker.onSkip = { [weak self] in self?.finishDestination(choosing: nil) }
        if let sheet = picker.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(picker, animated: true)
    }

    private func finishDestination(choosing code: String?) {
        if let code { applyDestination(code) }
        setFirstRun(firstRun.afterDestination)
        if !isDemo, !sessionStarted { startSession() }
    }

    /// Replays the walkthrough from the destination picker. Opened by the
    /// `psybeam://try` link that the "Try It Before Your Trip" in-app event
    /// deep-links to; consent still comes first for anyone who hasn't given it.
    func replayWalkthrough() {
        guard !isDemo else { return }
        setFirstRun(.chooseDestination)
        refreshResting()
        guard presentedViewController == nil else {
            dismiss(animated: true) { [weak self] in self?.beginReplayedWalkthrough() }
            return
        }
        beginReplayedWalkthrough()
    }

    private func beginReplayedWalkthrough() {
        if needsConsent {
            presentConsent()
        } else {
            presentDestinationPicker()
        }
    }

    /// The screen takes the new pair now rather than on the view model's next
    /// main-queue delivery, so the coach step that follows, and its VoiceOver
    /// announcement, name the language just picked.
    private func applyDestination(_ code: String) {
        #if DEBUG
        if isDemo {
            showDemoPair(displayedPair.choosingLocal(code))
            return
        }
        #endif
        viewModel.setLocalLanguage(code)
        updateLanguages(viewModel.pair)
    }

    /// Released without anything being translated: drop the dangling prompt and
    /// bring back the resting caption (the last reply, or the idle hint), facing
    /// whoever it was meant for.
    private func restoreResting() {
        if hasTranslation { setAudience(translationAudience) }
        refreshResting()
        UIView.animate(withDuration: 0.25) {
            self.promptLabel.alpha = 0
            self.translatedLabel.alpha = 1
        }
    }

    /// Everything the screen says between turns: why nothing can happen yet
    /// (no consent), the first-run coach, or the idle hint. A translation on
    /// screen is left alone, and so is a turn in progress.
    private func refreshResting() {
        consentButton.isHidden = !needsConsent
        consentButtonClearance.isActive = needsConsent
        refreshCoach()
        guard heldSide == nil else { return }
        if needsConsent {
            hasTranslation = false
            sourceLabel.text = ""
            let explanation = String(localized: "Psybeam needs your OK to send speech to its cloud translator.")
            showResting(NSAttributedString(
                string: explanation, attributes: restingAttributes(size: 28, alpha: 0.85, style: .title1, maximumScale: 1.15)))
        } else if !hasTranslation {
            let placeholder = NSAttributedString(
                string: String(localized: "Hold a button and speak"),
                attributes: restingAttributes(size: 36, alpha: 0.55, style: .title1))
            showResting(coachText(for: firstRun, size: 28, style: .title1) ?? placeholder)
        }
    }

    private func showResting(_ caption: NSAttributedString) {
        translatedLabel.attributedText = caption
        setAudience(.traveler)
    }

    /// The coach's pointers: the button to hold next breathes, and once the
    /// caption area holds a translation for them, the next step moves to a
    /// line above the buttons. Both stand down while anyone is holding and
    /// while a released turn is still settling, so the button just let go of
    /// never breathes again for the moment before its turn completes.
    private func refreshCoach() {
        let idle = !needsConsent && heldSide == nil && pendingTurns.isEmpty
        let beckoning = idle ? firstRun.beckoning : nil
        meButton.setBeckoning(beckoning == .traveler)
        themButton.setBeckoning(beckoning == .local)
        let showsLine = idle && hasTranslation && firstRun == .holdTheirs
        coachLabel.attributedText = showsLine ? coachText(for: firstRun, size: 17, style: .headline) : nil
        UIView.animate(withDuration: 0.25) { self.coachLabel.alpha = showsLine ? 1 : 0 }
    }

    /// A coaching step's line, with each language in its button's colour. The
    /// button to hold is named as it is printed on the button; the language
    /// you'll hear is named in the UI language.
    private func coachText(for stage: FirstRunStage, size: CGFloat, style: UIFont.TextStyle) -> NSAttributedString? {
        let attributes = restingAttributes(size: size, alpha: 0.82, style: style)
        switch stage {
        case .holdYours:
            let yours = LanguageNames.endonym(displayedPair.traveler)
            let theirs = LanguageNames.inUILanguage(displayedPair.local)
            let line = String(localized: "Hold \(yours) and say something. You’ll hear it in \(theirs).")
            return highlight(line, [(yours, travelerAccent), (theirs, localAccent)], attributes)
        case .holdTheirs:
            let theirs = LanguageNames.endonym(displayedPair.local)
            let line = String(localized: "Now hold \(theirs) and answer — or let someone answer you.")
            return highlight(line, [(theirs, localAccent)], attributes)
        case .chooseDestination, .done:
            return nil
        }
    }

    private func highlight(
        _ text: String, _ marks: [(String, UIColor)], _ attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: attributes)
        let source = text as NSString
        for (word, color) in marks where !word.isEmpty {
            let range = source.range(of: word)
            if range.location != NSNotFound { result.addAttribute(.foregroundColor, value: color, range: range) }
        }
        return result
    }

    /// Resting text grows with Dynamic Type up to `maximumScale` times `size`.
    /// The consent explanation stops sooner: it shares the space above the
    /// talk buttons with its own button, and both must fit a 375×667 window.
    private func restingAttributes(
        size: CGFloat, alpha: CGFloat, style: UIFont.TextStyle, maximumScale: CGFloat = 1.4
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        paragraph.lineBreakStrategy = .standard
        let font = UIFontMetrics(forTextStyle: style).scaledFont(
            for: .systemFont(ofSize: size, weight: .bold), maximumPointSize: size * maximumScale, compatibleWith: traitCollection)
        return [.font: font, .foregroundColor: UIColor.white.withAlphaComponent(alpha), .paragraphStyle: paragraph]
    }

    private func setFirstRun(_ stage: FirstRunStage) {
        guard stage != firstRun else { return }
        firstRun = stage
        if !isDemo { AppSettings.firstRunStage = stage }
        refreshResting()
        if let line = coachText(for: stage, size: 17, style: .headline)?.string {
            UIAccessibility.post(notification: .announcement, argument: line)
        }
    }

    private func layoutVisualizer() {
        visualizer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(visualizer)
        NSLayoutConstraint.activate([
            visualizer.topAnchor.constraint(equalTo: view.topAnchor),
            visualizer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            visualizer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            visualizer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func layoutConvo() {
        convoRoot.translatesAutoresizingMaskIntoConstraints = false
        convoRoot.alpha = 0
        view.addSubview(convoRoot)
        pin(convoRoot)
        convoRoot.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleScreenTap)))

        configureLabels()
        configureGearButton()
        configureLanguageBar()
        configureTalkButtons()
        configureCloudBadge()
        configureConsentButton()
        applyFlip(animated: false)

        let buttonRow = UIStackView(arrangedSubviews: [meButton, themButton])
        buttonRow.axis = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 14
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        [statusLabel, promptLabel, translatedLabel, sourceLabel, consentButton, coachLabel, buttonRow, gearGlass, languageBarHost, cloudBadge]
            .forEach { convoRoot.addSubview($0) }

        NSLayoutConstraint.activate(captionPlacement() + [
            translatedLabel.leadingAnchor.constraint(equalTo: convoRoot.leadingAnchor, constant: 28),
            translatedLabel.trailingAnchor.constraint(equalTo: convoRoot.trailingAnchor, constant: -28),

            statusLabel.bottomAnchor.constraint(equalTo: translatedLabel.topAnchor, constant: -22),
            statusLabel.centerXAnchor.constraint(equalTo: convoRoot.centerXAnchor),

            sourceLabel.topAnchor.constraint(equalTo: translatedLabel.bottomAnchor, constant: 16),
            sourceLabel.leadingAnchor.constraint(equalTo: convoRoot.leadingAnchor, constant: 28),
            sourceLabel.trailingAnchor.constraint(equalTo: convoRoot.trailingAnchor, constant: -28),

            consentButton.topAnchor.constraint(equalTo: translatedLabel.bottomAnchor, constant: 28),
            consentButton.centerXAnchor.constraint(equalTo: convoRoot.centerXAnchor),
            consentButton.leadingAnchor.constraint(greaterThanOrEqualTo: convoRoot.leadingAnchor, constant: 28),
            consentButton.trailingAnchor.constraint(lessThanOrEqualTo: convoRoot.trailingAnchor, constant: -28),

            promptLabel.centerYAnchor.constraint(equalTo: convoRoot.centerYAnchor, constant: -158),
            promptLabel.leadingAnchor.constraint(equalTo: convoRoot.leadingAnchor, constant: 28),
            promptLabel.trailingAnchor.constraint(equalTo: convoRoot.trailingAnchor, constant: -28),

            buttonRow.leadingAnchor.constraint(equalTo: convoRoot.leadingAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: convoRoot.trailingAnchor, constant: -20),
            buttonRow.bottomAnchor.constraint(equalTo: convoRoot.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            buttonRow.heightAnchor.constraint(equalToConstant: 116),

            cloudBadge.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -10),
            cloudBadge.centerXAnchor.constraint(equalTo: convoRoot.centerXAnchor),

            coachLabel.bottomAnchor.constraint(equalTo: cloudBadge.topAnchor, constant: -16),
            coachLabel.leadingAnchor.constraint(equalTo: convoRoot.leadingAnchor, constant: 28),
            coachLabel.trailingAnchor.constraint(equalTo: convoRoot.trailingAnchor, constant: -28),

            gearGlass.topAnchor.constraint(equalTo: convoRoot.safeAreaLayoutGuide.topAnchor, constant: 8),
            gearGlass.leadingAnchor.constraint(equalTo: convoRoot.leadingAnchor, constant: 20),
            gearGlass.widthAnchor.constraint(equalToConstant: 46),
            gearGlass.heightAnchor.constraint(equalToConstant: 46),

            languageBarHost.centerYAnchor.constraint(equalTo: gearGlass.centerYAnchor),
            languageBarHost.centerXAnchor.constraint(equalTo: convoRoot.centerXAnchor),
            languageBarHost.leadingAnchor.constraint(greaterThanOrEqualTo: gearGlass.trailingAnchor, constant: 8),
            languageBarHost.trailingAnchor.constraint(lessThanOrEqualTo: convoRoot.trailingAnchor, constant: -20),
            languageBarHost.heightAnchor.constraint(equalToConstant: 42),
        ])
    }

    /// The caption sits just above centre, but gives way upward rather than let
    /// it and its source line run into the coach line above the buttons. That
    /// happens with a long caption on the smallest screens, including the
    /// 375×667 window an iPad runs this iPhone app in. Centring ranks just
    /// below the labels' compression resistance, so the caption moves instead
    /// of the coach line or the cloud badge being squeezed.
    private func captionPlacement() -> [NSLayoutConstraint] {
        let center = translatedLabel.centerYAnchor.constraint(equalTo: convoRoot.centerYAnchor, constant: -40)
        center.priority = .defaultHigh - 1
        return [center, coachLabel.topAnchor.constraint(greaterThanOrEqualTo: sourceLabel.bottomAnchor, constant: 12)]
    }

    /// A flat translucent pill, deliberately NOT a glass effect view: live glass
    /// over the 60fps Metal aurora re-samples the moving colours every frame —
    /// which tinted the bar with shifting hues (worst on cold launch) and cost a
    /// full blur pass per frame. A solid host is also immune to the menu-morph
    /// snapshot that broke the corner radius.
    private func configureLanguageBar() {
        languageBarHost.translatesAutoresizingMaskIntoConstraints = false
        languageBarHost.backgroundColor = UIColor(white: 0.05, alpha: 0.6)
        languageBarHost.layer.cornerRadius = 21
        languageBarHost.layer.cornerCurve = .continuous
        languageBarHost.clipsToBounds = true
        languageBarHost.layer.borderWidth = 1
        languageBarHost.layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor

        for button in [youLangButton, themLangButton] {
            button.showsMenuAsPrimaryAction = true
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold))
            config.imagePlacement = .trailing
            config.imagePadding = 3
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            button.configuration = config
        }
        youLangButton.tintColor = travelerAccent
        themLangButton.tintColor = localAccent
        youLangButton.accessibilityHint = String(localized: "Change the language you speak")
        themLangButton.accessibilityHint = String(localized: "Change the language they speak")

        var swap = UIButton.Configuration.plain()
        swap.image = UIImage(systemName: "arrow.left.arrow.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        swap.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 3, bottom: 6, trailing: 3)
        swapButton.configuration = swap
        swapButton.tintColor = UIColor.white.withAlphaComponent(0.7)
        swapButton.accessibilityLabel = String(localized: "Swap languages")
        swapButton.addTarget(self, action: #selector(swapLanguages), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [youLangButton, swapButton, themLangButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        languageBarHost.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: languageBarHost.topAnchor),
            stack.bottomAnchor.constraint(equalTo: languageBarHost.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: languageBarHost.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: languageBarHost.trailingAnchor, constant: -6),
        ])
    }

    private func makeLangMenu(isTraveler: Bool) -> UIMenu {
        let selected = isTraveler ? viewModel.pair.traveler : viewModel.pair.local
        let actions = SupportedLanguages.codes.map { code in
            UIAction(title: LanguageNames.endonym(code), state: code == selected ? .on : .off) { [weak self] _ in
                self?.chooseLanguage(code, isTraveler: isTraveler)
            }
        }
        return UIMenu(title: isTraveler ? String(localized: "You speak") : String(localized: "They speak"), children: actions)
    }

    /// Changing a language by hand means the user has found their way around the
    /// screen, so the first-run coach stands down. Re-selecting the language
    /// already set changes nothing, the coach included, as in Settings.
    private func chooseLanguage(_ code: String, isTraveler: Bool) {
        let before = viewModel.pair
        if isTraveler { viewModel.setTravelerLanguage(code) } else { viewModel.setLocalLanguage(code) }
        if viewModel.pair != before { setFirstRun(.done) }
    }

    private func setLangButtonTitle(_ button: UIButton, _ text: String, _ color: UIColor) {
        button.configuration?.attributedTitle = AttributedString(text, attributes: AttributeContainer([
            .font: UIFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: color,
        ]))
    }

    @objc private func swapLanguages() {
        impact.impactOccurred()
        viewModel.swapLanguages()
        setFirstRun(.done)
    }

    private func configureLabels() {
        statusLabel.font = .systemFont(ofSize: 14, weight: .heavy)
        statusLabel.textColor = .clear
        statusLabel.textAlignment = .center
        statusLabel.setContentHuggingPriority(.required, for: .vertical)

        translatedLabel.font = Self.captionFont
        translatedLabel.adjustsFontForContentSizeCategory = true
        translatedLabel.textColor = .white
        translatedLabel.textAlignment = .center
        translatedLabel.numberOfLines = 0

        promptLabel.font = .systemFont(ofSize: 34, weight: .heavy)
        promptLabel.adjustsFontForContentSizeCategory = true
        promptLabel.textColor = .white
        promptLabel.textAlignment = .center
        promptLabel.numberOfLines = 0
        promptLabel.alpha = 0

        sourceLabel.font = .systemFont(ofSize: 17, weight: .medium)
        sourceLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        sourceLabel.textAlignment = .center
        sourceLabel.numberOfLines = 0

        coachLabel.textAlignment = .center
        coachLabel.numberOfLines = 0
        coachLabel.alpha = 0

        for label in [statusLabel, translatedLabel, sourceLabel, promptLabel, coachLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.55
            label.layer.shadowRadius = 10
            label.layer.shadowOffset = .zero
            label.layer.masksToBounds = false
        }
    }

    /// The way back from "Not now": the resting caption says why nothing
    /// happens, and this reopens the consent sheet. Tapping anywhere on the
    /// screen, or holding a talk button, does the same.
    private func configureConsentButton() {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = brand
        config.baseForegroundColor = .white
        config.image = UIImage(systemName: "cloud.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        config.imagePadding = 8
        config.attributedTitle = AttributedString(String(localized: "Review consent"), attributes: AttributeContainer([
            .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 17, weight: .semibold), maximumPointSize: 26),
        ]))
        config.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 22, bottom: 13, trailing: 22)
        consentButton.configuration = config
        consentButton.translatesAutoresizingMaskIntoConstraints = false
        consentButton.isHidden = true
        consentButton.addAction(UIAction { [weak self] _ in self?.presentConsent() }, for: .touchUpInside)
    }

    private func configureTalkButtons() {
        meButton.onPress = { [weak self] in self?.pressBegan(.traveler) ?? false }
        meButton.onRelease = { [weak self] in self?.pressEnded(.traveler) }
        themButton.onPress = { [weak self] in self?.pressBegan(.local) ?? false }
        themButton.onRelease = { [weak self] in self?.pressEnded(.local) }
    }

    /// The honest-floor indicator for the bystander who can't consent to cloud
    /// routing: a persistent, neutral (not blue/green) "cloud AI" mark. Never
    /// claims on-device.
    private func configureCloudBadge() {
        let attachment = NSTextAttachment()
        attachment.image = UIImage(systemName: "cloud.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))?
            .withTintColor(UIColor.white.withAlphaComponent(0.5), renderingMode: .alwaysOriginal)
        let text = NSMutableAttributedString(attachment: attachment)
        text.append(NSAttributedString(string: "  " + String(localized: "Cloud AI"), attributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.5),
        ]))
        cloudBadge.attributedText = text
        cloudBadge.textAlignment = .center
        cloudBadge.translatesAutoresizingMaskIntoConstraints = false
        cloudBadge.isAccessibilityElement = true
        cloudBadge.accessibilityLabel = String(localized: "Translated by cloud AI")
    }

    /// Returns whether the hold started. A press without consent re-presents
    /// the consent sheet and one with the microphone denied shows how to fix
    /// it; neither lights the button, since nothing is listening.
    private func pressBegan(_ speaker: Side) -> Bool {
        guard AppSettings.aiConsentGranted else {
            presentConsent()
            return false
        }
        if AVAudioApplication.shared.recordPermission == .denied {
            render(legState: .permissionDenied(.microphone), speaker: speaker)
            return false
        }
        impact.impactOccurred()
        release.prepare()
        beginHold(speaker)
        viewModel.holdDown(speaker)
        return true
    }

    private func pressEnded(_ speaker: Side) {
        release.impactOccurred()
        impact.prepare()
        viewModel.holdUp(speaker)
        endHold()
    }

    /// Screen-side bookkeeping for a hold, shared by live holds and scripted
    /// demo holds so both drive the same coach and caption state.
    private func beginHold(_ speaker: Side) {
        heldSide = speaker
        turnProducedText = false
        pendingTurns.insert(speaker)
        refreshCoach()
    }

    private func endHold() {
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
    private func abandonPendingTurns() {
        pendingTurns.removeAll()
        refreshCoach()
    }

    /// The closing delta of a turn — give it a body: a success tap and a small
    /// settle so the caption reads as committed, not merely paused mid-stream.
    private func onTurnFinished(_ speaker: Side) {
        notify.notificationOccurred(.success)
        notify.prepare()
        if !isDemo { ReviewPrompt.recordCompletedTurn(in: view.window?.windowScene) }
        pendingTurns.remove(speaker)
        setFirstRun(firstRun.after(turnBy: speaker))
        refreshCoach()
        let base = translatedLabel.transform
        UIView.animate(withDuration: 0.14, animations: {
            self.translatedLabel.transform = base.scaledBy(x: 1.035, y: 1.035)
        }, completion: { _ in
            UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.4) {
                self.translatedLabel.transform = base
            }
        })
    }

    private func configureGearButton() {
        gearGlass.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect()
            effect.isInteractive = true
            gearGlass.effect = effect
        } else {
            gearGlass.effect = UIBlurEffect(style: .systemThinMaterialDark)
        }
        gearGlass.layer.cornerRadius = 23
        gearGlass.layer.cornerCurve = .continuous
        gearGlass.clipsToBounds = true
        gearIcon.image = UIImage(systemName: "gearshape.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))
        gearIcon.tintColor = .white
        gearIcon.contentMode = .center
        gearIcon.translatesAutoresizingMaskIntoConstraints = false
        gearGlass.contentView.addSubview(gearIcon)
        NSLayoutConstraint.activate([
            gearIcon.centerXAnchor.constraint(equalTo: gearGlass.contentView.centerXAnchor),
            gearIcon.centerYAnchor.constraint(equalTo: gearGlass.contentView.centerYAnchor),
        ])
        gearGlass.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openSettings)))
        gearGlass.isAccessibilityElement = true
        gearGlass.accessibilityLabel = String(localized: "Settings")
    }

    /// Settings can withdraw consent or change either language, so the resting
    /// state is recomputed when it closes; a changed pair ends the coach just
    /// as it does from the language bar.
    @objc private func openSettings() {
        impact.impactOccurred()
        visualizer.setPaused(true)
        let settings = SettingsViewController(
            viewModel: viewModel,
            onBrightnessChanged: { [weak self] in self?.applyMaxBrightness() }
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
    private func applyFlip(animated: Bool) {
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

    private func setAudience(_ audience: Side) {
        guard displayAudience != audience else { return }
        displayAudience = audience
        applyFlip(animated: true)
    }

    private func updateLanguages(_ pair: LanguagePair) {
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

    private func pin(_ subview: UIView) {
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: view.topAnchor),
            subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func requestMicPermission() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard !granted else { return }
            Task { @MainActor in
                self?.render(legState: .permissionDenied(.microphone), speaker: .traveler)
            }
        }
    }

    /// Opens the Settings app while mic access is denied, and the consent sheet
    /// while consent is missing; otherwise taps are inert, so this never
    /// competes with the hold-to-talk buttons during normal use.
    @objc private func handleScreenTap() {
        if micDenied, let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        } else if needsConsent {
            presentConsent()
        }
    }

    private func recheckMicPermission() {
        guard micDenied, AVAudioApplication.shared.recordPermission == .granted else { return }
        micDenied = false
        render(legState: .idle, speaker: .traveler)
    }

    private static func speakPrompt(for code: String) -> String {
        let base = String(code.prefix(2)).lowercased()
        return prompts[base] ?? "Speak now"
    }

    private static let prompts: [String: String] = [
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

#if DEBUG
extension ConversationViewController: DemoStage {
    func demoHold(_ speaker: Side) {
        talkButton(for: speaker).setActive(true)
        beginHold(speaker)
        handleText("", speaker: speaker)
        sourceLabel.text = ""
        render(legState: .listening(turn: speaker, level: 0), speaker: speaker)
    }

    func demoRelease(_ speaker: Side) {
        talkButton(for: speaker).setActive(false)
        render(legState: .idle, speaker: speaker)
        endHold()
    }

    func demoCaption(_ text: String, speaker: Side) {
        handleText(text, speaker: speaker)
    }

    func demoSource(_ text: String) {
        sourceLabel.text = text
    }

    func demoState(_ state: TranslationState, speaker: Side) {
        render(legState: state, speaker: speaker)
    }

    func demoPair(_ pair: LanguagePair) {
        showDemoPair(pair)
    }

    func demoLevel(_ level: Float) {
        visualizer.setLevel(level)
    }

    func demoTurnFinished(_ speaker: Side) {
        onTurnFinished(speaker)
    }

    private func showDemoPair(_ pair: LanguagePair) {
        viewModel.showDemoPair(pair)
        updateLanguages(pair)
    }

    private func talkButton(for speaker: Side) -> TalkButton {
        speaker == .traveler ? meButton : themButton
    }

    /// A still of one phrase-table line mid-turn (the button held, the caption
    /// facing its listener), or finished and released when `finished`.
    private func showDemoTurn(line: Int, finished: Bool) {
        guard let book = demo?.phrasebook else { return }
        let speaker = DemoPhrasebook.speaker(ofLine: line)
        demoHold(speaker)
        demoSource(book.source(line: line))
        demoCaption(book.caption(line: line), speaker: speaker)
        guard finished else { return }
        demoRelease(speaker)
        demoTurnFinished(speaker)
    }

    private func presentDemoSheet(for mode: String) {
        switch mode {
        case "settings": openSettings()
        case "consent": presentConsent()
        case "destination": presentDestinationPicker()
        default: break
        }
    }

    private func startDemoScriptIfNeeded() {
        guard let demo, demo.mode == "script", demoPlayer == nil else { return }
        let player = DemoScriptPlayer(events: demo.script, phrasebook: demo.phrasebook, stage: self)
        demoPlayer = player
        player.start()
    }
}
#endif
