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
    private let cloudBadge = UILabel()
    private let gearGlass = UIVisualEffectView()
    private let gearIcon = UIImageView()
    private let languageBarHost = UIView()
    private let youLangButton = UIButton(type: .system)
    private let themLangButton = UIButton(type: .system)
    private let swapButton = UIButton(type: .system)

    private let languages = ["en", "es", "fr", "de", "it", "pt", "nl", "ru", "pl", "tr", "el", "ar", "he", "hi", "ja", "ko", "zh", "th", "vi", "id", "fi", "sv"]

    private let travelerAccent = UIColor(red: 0.34, green: 0.74, blue: 1.0, alpha: 1)
    private let localAccent = UIColor(red: 0.42, green: 1.0, blue: 0.72, alpha: 1)
    private let errorRed = UIColor(red: 1.0, green: 0.32, blue: 0.36, alpha: 1)
    private let amber = UIColor(red: 1.0, green: 0.66, blue: 0.22, alpha: 1)
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
    private var hasTranslation = false
    private var turnProducedText = false
    private var needsConsentOnAppear = false
    private var micDenied = false

    init(viewModel: ConversationViewModel) {
        self.viewModel = viewModel
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
        }
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
        }
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        layoutVisualizer()
        layoutConvo()
        bind()
        if !applyPreviewIfNeeded() {
            convoRoot.alpha = 1
            if AppSettings.aiConsentGranted {
                startSession()
            } else {
                needsConsentOnAppear = true
            }
        }
    }

    @discardableResult
    private func applyPreviewIfNeeded() -> Bool {
        #if DEBUG
        guard let demo = ProcessInfo.processInfo.environment["PSYBEAM_DEMO"] else { return false }
        convoRoot.alpha = 1
        updateLanguages(LanguagePair(traveler: "en", local: "fr"))
        switch demo {
        case "listening":
            render(legState: .listening(turn: .traveler, level: 0.7), speaker: .traveler)
            handleText("Où est la pharmacie la plus proche ?", speaker: .traveler)
        case "them":
            render(legState: .listening(turn: .local, level: 0.7), speaker: .local)
            handleText("It's just around the corner, on the left.", speaker: .local)
        default:
            handleText("", speaker: .traveler)
        }
        visualizer.setLevel(0.6)
        if demo == "settings" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.openSettings() }
        }
        if demo == "consent" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.presentConsent() }
        }
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
        viewModel.travelerLeg.finishedPublisher
            .merge(with: viewModel.localLeg.finishedPublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.onTurnFinished() }
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
            .sink { [weak self] result in self?.viewModel.applyDetectedLanguage(result.language) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.viewModel.end()
                self?.restoreBrightness()
                self?.visualizer.setPaused(true)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.visualizer.setPaused(false)
                self?.applyMaxBrightness()
                self?.primeHaptics()
                self?.recheckMicPermission()
                if AppSettings.aiConsentGranted { self?.viewModel.warmUp() }
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
        let spokenLanguage = speaker == .traveler ? viewModel.pair.traveler : viewModel.pair.local
        let audience: Side = text.isEmpty ? speaker : speaker.other
        if displayAudience != audience {
            displayAudience = audience
            applyFlip(animated: true)
        }
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
            translatedLabel.text = text
            translatedLabel.textColor = .white
            UIView.animate(withDuration: 0.2) {
                self.promptLabel.alpha = 0
                self.translatedLabel.alpha = 1
            }
        }
    }

    private func startSession() {
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
            AppSettings.aiConsentGranted = true
            self?.dismiss(animated: true) { self?.startSession() }
        }
        consent.onDecline = { [weak self] in
            self?.dismiss(animated: true)
        }
        if let sheet = consent.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }
        present(consent, animated: true)
    }

    /// Released without anything being translated: drop the dangling prompt and
    /// bring back the resting caption (the last reply, or the idle hint).
    private func restoreResting() {
        UIView.animate(withDuration: 0.25) {
            self.promptLabel.alpha = 0
            self.translatedLabel.alpha = 1
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
        applyFlip(animated: false)

        let buttonRow = UIStackView(arrangedSubviews: [meButton, themButton])
        buttonRow.axis = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 14
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        [statusLabel, promptLabel, translatedLabel, sourceLabel, buttonRow, gearGlass, languageBarHost, cloudBadge].forEach { convoRoot.addSubview($0) }

        NSLayoutConstraint.activate([
            translatedLabel.centerYAnchor.constraint(equalTo: convoRoot.centerYAnchor, constant: -40),
            translatedLabel.leadingAnchor.constraint(equalTo: convoRoot.leadingAnchor, constant: 28),
            translatedLabel.trailingAnchor.constraint(equalTo: convoRoot.trailingAnchor, constant: -28),

            statusLabel.bottomAnchor.constraint(equalTo: translatedLabel.topAnchor, constant: -22),
            statusLabel.centerXAnchor.constraint(equalTo: convoRoot.centerXAnchor),

            sourceLabel.topAnchor.constraint(equalTo: translatedLabel.bottomAnchor, constant: 16),
            sourceLabel.leadingAnchor.constraint(equalTo: convoRoot.leadingAnchor, constant: 28),
            sourceLabel.trailingAnchor.constraint(equalTo: convoRoot.trailingAnchor, constant: -28),

            promptLabel.centerYAnchor.constraint(equalTo: convoRoot.centerYAnchor, constant: -158),
            promptLabel.leadingAnchor.constraint(equalTo: convoRoot.leadingAnchor, constant: 28),
            promptLabel.trailingAnchor.constraint(equalTo: convoRoot.trailingAnchor, constant: -28),

            buttonRow.leadingAnchor.constraint(equalTo: convoRoot.leadingAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: convoRoot.trailingAnchor, constant: -20),
            buttonRow.bottomAnchor.constraint(equalTo: convoRoot.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            buttonRow.heightAnchor.constraint(equalToConstant: 116),

            cloudBadge.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -10),
            cloudBadge.centerXAnchor.constraint(equalTo: convoRoot.centerXAnchor),

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
        let actions = languages.map { code in
            UIAction(title: Self.endonym(code), state: code == selected ? .on : .off) { [weak self] _ in
                if isTraveler { self?.viewModel.setTravelerLanguage(code) } else { self?.viewModel.setLocalLanguage(code) }
            }
        }
        return UIMenu(title: isTraveler ? String(localized: "You speak") : String(localized: "They speak"), children: actions)
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
    }

    private func configureLabels() {
        statusLabel.font = .systemFont(ofSize: 14, weight: .heavy)
        statusLabel.textColor = .clear
        statusLabel.textAlignment = .center
        statusLabel.setContentHuggingPriority(.required, for: .vertical)

        translatedLabel.font = .systemFont(ofSize: 36, weight: .bold)
        translatedLabel.adjustsFontForContentSizeCategory = true
        translatedLabel.textColor = .white
        translatedLabel.textAlignment = .center
        translatedLabel.numberOfLines = 0
        translatedLabel.text = String(localized: "Hold a button and speak")
        translatedLabel.textColor = UIColor.white.withAlphaComponent(0.55)

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

        for label in [statusLabel, translatedLabel, sourceLabel, promptLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.55
            label.layer.shadowRadius = 10
            label.layer.shadowOffset = .zero
            label.layer.masksToBounds = false
        }
    }

    private func configureTalkButtons() {
        meButton.onHold = { [weak self] down in self?.hold(.traveler, down: down) }
        themButton.onHold = { [weak self] down in self?.hold(.local, down: down) }
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

    private func hold(_ speaker: Side, down: Bool) {
        if down {
            guard AppSettings.aiConsentGranted else { presentConsent(); return }
            if AVAudioApplication.shared.recordPermission == .denied {
                render(legState: .permissionDenied(.microphone), speaker: speaker)
                return
            }
            impact.impactOccurred()
            release.prepare()
            turnProducedText = false
            viewModel.holdDown(speaker)
        } else {
            release.impactOccurred()
            impact.prepare()
            viewModel.holdUp(speaker)
            if !turnProducedText { restoreResting() }
        }
    }

    /// The closing delta of a turn — give it a body: a success tap and a small
    /// settle so the caption reads as committed, not merely paused mid-stream.
    private func onTurnFinished() {
        notify.notificationOccurred(.success)
        notify.prepare()
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

    @objc private func openSettings() {
        impact.impactOccurred()
        visualizer.setPaused(true)
        let settings = SettingsViewController(
            viewModel: viewModel,
            onBrightnessChanged: { [weak self] in self?.applyMaxBrightness() }
        )
        settings.onDismiss = { [weak self] in self?.visualizer.setPaused(false) }
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

    private func updateLanguages(_ pair: LanguagePair) {
        meButton.languageLabel.text = Self.endonym(pair.traveler)
        themButton.languageLabel.text = Self.endonym(pair.local)
        meButton.accessibilityLabel = String(localized: "Hold to speak \(Self.endonym(pair.traveler))")
        themButton.accessibilityLabel = String(localized: "Hold while they speak \(Self.endonym(pair.local))")
        setLangButtonTitle(youLangButton, Self.endonym(pair.traveler), travelerAccent)
        setLangButtonTitle(themLangButton, Self.endonym(pair.local), localAccent)
        youLangButton.menu = makeLangMenu(isTraveler: true)
        themLangButton.menu = makeLangMenu(isTraveler: false)
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
        AVAudioApplication.requestRecordPermission { _ in }
    }

    /// Only acts while mic access is denied — taps are otherwise inert, so this
    /// never competes with the hold-to-talk buttons during normal use.
    @objc private func handleScreenTap() {
        guard micDenied, let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func recheckMicPermission() {
        guard micDenied, AVAudioApplication.shared.recordPermission == .granted else { return }
        micDenied = false
        render(legState: .idle, speaker: .traveler)
    }

    private static func endonym(_ code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
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
