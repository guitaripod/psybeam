import AuthenticationServices
import AVFAudio
import Combine
import PsybeamKit
import UIKit

final class ConversationViewController: UIViewController {
    private let viewModel: ConversationViewModel
    private let auth: AuthService
    private let worker: WorkerClient
    private let location = LocationLanguageService()
    private var cancellables = Set<AnyCancellable>()

    private let visualizer = WaveVisualizerView()
    private let convoRoot = UIView()
    private let authRoot = UIView()

    private let signInButton = ASAuthorizationAppleIDButton(type: .signIn, style: .whiteOutline)
    private let statusLabel = UILabel()
    private let translatedLabel = UILabel()
    private let sourceLabel = UILabel()
    private let gearGlass = UIVisualEffectView()
    private let gearIcon = UIImageView()
    private let languageBarHost = UIView()
    private let youLangButton = UIButton(type: .system)
    private let themLangButton = UIButton(type: .system)
    private let swapButton = UIButton(type: .system)

    private let languages = ["en", "es", "fr", "de", "it", "pt", "nl", "ru", "pl", "tr", "el", "ar", "he", "hi", "ja", "ko", "zh", "th", "vi", "id", "fi", "sv"]

    private let travelerAccent = UIColor(red: 0.34, green: 0.74, blue: 1.0, alpha: 1)
    private let localAccent = UIColor(red: 0.42, green: 1.0, blue: 0.72, alpha: 1)
    private lazy var meButton = TalkButton(accent: travelerAccent, hint: "HOLD · YOU", micSymbol: "mic.fill")
    private lazy var themButton = TalkButton(accent: localAccent, hint: "HOLD · THEM", micSymbol: "person.wave.2.fill")

    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let release = UIImpactFeedbackGenerator(style: .soft)
    private let notify = UINotificationFeedbackGenerator()
    private var savedBrightness: CGFloat?
    private var travelerText = ""
    private var localText = ""
    private var displayAudience: Side = .traveler

    init(viewModel: ConversationViewModel, auth: AuthService, worker: WorkerClient) {
        self.viewModel = viewModel
        self.auth = auth
        self.worker = worker
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyMaxBrightness()
        primeHaptics()
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
        layoutAuth()
        bind()
        if !applyPreviewIfNeeded() {
            let signedIn = auth.isSignedIn
            authRoot.alpha = signedIn ? 0 : 1
            convoRoot.alpha = signedIn ? 1 : 0
            if signedIn {
                requestMicPermission()
                location.start()
                viewModel.start()
                viewModel.warmUp()
            }
            auth.restore()
        }
    }

    @discardableResult
    private func applyPreviewIfNeeded() -> Bool {
        #if DEBUG
        guard let demo = ProcessInfo.processInfo.environment["PSYBEAM_DEMO"] else { return false }
        authRoot.alpha = 0
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
        return true
        #else
        return false
        #endif
    }

    private func bind() {
        auth.state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.render(auth: state) }
            .store(in: &cancellables)
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
                if self?.auth.isSignedIn == true { self?.viewModel.warmUp() }
            }
            .store(in: &cancellables)
    }

    private func render(auth state: AuthState) {
        let signedIn: Bool
        switch state {
        case .signedIn: signedIn = true
        default: signedIn = false
        }
        if signedIn {
            requestMicPermission()
            location.start()
            viewModel.start()
            viewModel.warmUp()
        }
        UIView.animate(withDuration: 0.45, delay: 0, options: .curveEaseInOut) {
            self.authRoot.alpha = signedIn ? 0 : 1
            self.convoRoot.alpha = signedIn ? 1 : 0
        }
    }

    private func render(legState state: TranslationState, speaker: Side) {
        switch state {
        case .listening:
            visualizer.apply(speaker == .traveler ? .listening : .speaking)
            setStatus("LISTENING", color: speaker == .traveler ? travelerAccent : localAccent)
        case .processing:
            visualizer.apply(.processing)
            setStatus("CONNECTING", color: UIColor(red: 1.0, green: 0.66, blue: 0.22, alpha: 1))
        case .reconnecting:
            visualizer.apply(.processing)
            setStatus("RECONNECTING", color: UIColor(red: 1.0, green: 0.66, blue: 0.22, alpha: 1))
        case .error:
            visualizer.apply(.error)
            setStatus("HOLD TO RETRY", color: UIColor(red: 1.0, green: 0.32, blue: 0.36, alpha: 1))
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

    /// While a turn is opening, `text` arrives empty — that's the cue to invite
    /// the upcoming speaker in *their own* language so a stranger knows to talk.
    private func handleText(_ text: String, speaker: Side) {
        if speaker == .traveler { travelerText = text } else { localText = text }
        let spokenLanguage = speaker == .traveler ? viewModel.pair.traveler : viewModel.pair.local
        let audience: Side = text.isEmpty ? speaker : speaker.other
        if displayAudience != audience {
            displayAudience = audience
            applyFlip(animated: true)
        }
        if text.isEmpty {
            translatedLabel.text = Self.speakPrompt(for: spokenLanguage)
            translatedLabel.textColor = (speaker == .traveler ? travelerAccent : localAccent).withAlphaComponent(0.85)
        } else {
            translatedLabel.text = text
            translatedLabel.textColor = .white
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

        configureLabels()
        configureGearButton()
        configureLanguageBar()
        configureTalkButtons()
        applyFlip(animated: false)

        let buttonRow = UIStackView(arrangedSubviews: [meButton, themButton])
        buttonRow.axis = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 14
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        [statusLabel, translatedLabel, sourceLabel, buttonRow, gearGlass, languageBarHost].forEach { convoRoot.addSubview($0) }

        NSLayoutConstraint.activate([
            translatedLabel.centerYAnchor.constraint(equalTo: convoRoot.centerYAnchor, constant: -40),
            translatedLabel.leadingAnchor.constraint(equalTo: convoRoot.leadingAnchor, constant: 28),
            translatedLabel.trailingAnchor.constraint(equalTo: convoRoot.trailingAnchor, constant: -28),

            statusLabel.bottomAnchor.constraint(equalTo: translatedLabel.topAnchor, constant: -22),
            statusLabel.centerXAnchor.constraint(equalTo: convoRoot.centerXAnchor),

            sourceLabel.topAnchor.constraint(equalTo: translatedLabel.bottomAnchor, constant: 16),
            sourceLabel.leadingAnchor.constraint(equalTo: convoRoot.leadingAnchor, constant: 28),
            sourceLabel.trailingAnchor.constraint(equalTo: convoRoot.trailingAnchor, constant: -28),

            buttonRow.leadingAnchor.constraint(equalTo: convoRoot.leadingAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: convoRoot.trailingAnchor, constant: -20),
            buttonRow.bottomAnchor.constraint(equalTo: convoRoot.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            buttonRow.heightAnchor.constraint(equalToConstant: 116),

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
        youLangButton.accessibilityHint = "Change the language you speak"
        themLangButton.accessibilityHint = "Change the language they speak"

        var swap = UIButton.Configuration.plain()
        swap.image = UIImage(systemName: "arrow.left.arrow.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        swap.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 3, bottom: 6, trailing: 3)
        swapButton.configuration = swap
        swapButton.tintColor = UIColor.white.withAlphaComponent(0.7)
        swapButton.accessibilityLabel = "Swap languages"
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
        return UIMenu(title: isTraveler ? "You speak" : "They speak", children: actions)
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
        translatedLabel.text = "Hold a button and speak"
        translatedLabel.textColor = UIColor.white.withAlphaComponent(0.55)

        sourceLabel.font = .systemFont(ofSize: 17, weight: .medium)
        sourceLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        sourceLabel.textAlignment = .center
        sourceLabel.numberOfLines = 0

        for label in [statusLabel, translatedLabel, sourceLabel] {
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

    private func hold(_ speaker: Side, down: Bool) {
        if down {
            impact.impactOccurred()
            release.prepare()
            viewModel.holdDown(speaker)
        } else {
            release.impactOccurred()
            impact.prepare()
            viewModel.holdUp(speaker)
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
        gearGlass.accessibilityLabel = "Settings"
    }

    @objc private func openSettings() {
        impact.impactOccurred()
        visualizer.setPaused(true)
        let settings = SettingsViewController(
            viewModel: viewModel,
            auth: auth,
            worker: worker,
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
        if animated {
            UIView.animate(withDuration: 0.45, delay: 0, options: .curveEaseInOut) {
                self.translatedLabel.transform = transform
            }
        } else {
            translatedLabel.transform = transform
        }
    }

    private func layoutAuth() {
        authRoot.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(authRoot)
        pin(authRoot)

        let title = UILabel()
        title.text = "Psybeam"
        title.font = .systemFont(ofSize: 40, weight: .bold)
        title.textColor = .white
        title.textAlignment = .center
        let subtitle = UILabel()
        subtitle.text = "You speak. They hear it. They reply. You hear it."
        subtitle.font = .preferredFont(forTextStyle: .body)
        subtitle.textColor = UIColor.white.withAlphaComponent(0.7)
        subtitle.numberOfLines = 0
        subtitle.textAlignment = .center

        signInButton.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)
        signInButton.cornerRadius = 14
        signInButton.translatesAutoresizingMaskIntoConstraints = false
        signInButton.heightAnchor.constraint(equalToConstant: 52).isActive = true

        let stack = UIStackView(arrangedSubviews: [title, subtitle, signInButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.setCustomSpacing(36, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        authRoot.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: authRoot.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: authRoot.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(equalTo: authRoot.trailingAnchor, constant: -36),
        ])
    }

    private func updateLanguages(_ pair: LanguagePair) {
        meButton.languageLabel.text = Self.endonym(pair.traveler)
        themButton.languageLabel.text = Self.endonym(pair.local)
        meButton.accessibilityLabel = "Hold to speak \(Self.endonym(pair.traveler))"
        themButton.accessibilityLabel = "Hold while they speak \(Self.endonym(pair.local))"
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

    @objc private func signInTapped() { auth.signIn() }

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
    ]
}
