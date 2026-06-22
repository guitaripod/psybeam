import AVFoundation
import Combine
import MidgarKit
import PsybeamKit
import SwiftUI
import UIKit
import AICreditsUI

final class SettingsViewController: UIViewController {
    private let viewModel: ConversationViewModel
    private let onBrightnessChanged: () -> Void
    var onDismiss: (() -> Void)?

    private let gradient = CAGradientLayer()
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private let youButton = UIButton(type: .system)
    private let themButton = UIButton(type: .system)
    private let minutesLabel = UILabel()
    private let micModeValue = UILabel()
    private var micModeTimer: Timer?
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private var cancellables = Set<AnyCancellable>()

    private let brand = UIColor(red: 0.30, green: 0.62, blue: 1.0, alpha: 1)
    private let languages = ["en", "es", "fr", "de", "it", "pt", "nl", "ru", "pl", "tr", "el", "ar", "he", "hi", "ja", "ko", "zh", "th", "vi", "id", "fi", "sv"]

    init(
        viewModel: ConversationViewModel,
        onBrightnessChanged: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onBrightnessChanged = onBrightnessChanged
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.layer.insertSublayer(gradient, at: 0)
        buildLayout()
        refreshLanguageButtons()
        observeBalance()
        fetchBalance()
        refreshMicMode()
        applyAdaptiveChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: SettingsViewController, _) in
            self.applyAdaptiveChrome()
        }
        impact.prepare()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradient.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshMicMode()
        fetchBalance()
        micModeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshMicMode()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        micModeTimer?.invalidate()
        micModeTimer = nil
        if presentingViewController == nil || isBeingDismissed { onDismiss?() }
    }

    private func applyAdaptiveChrome() {
        let top = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.08, blue: 0.17, alpha: 1)
            : UIColor(red: 0.95, green: 0.96, blue: 1.0, alpha: 1) }
        let bottom = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1)
            : UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1) }
        gradient.colors = [top.resolvedColor(with: traitCollection).cgColor, bottom.resolvedColor(with: traitCollection).cgColor]
        setNeedsStatusBarAppearanceUpdate()
    }

    private func buildLayout() {
        let title = UILabel()
        title.text = "Settings"
        title.font = .systemFont(ofSize: 32, weight: .bold)
        title.textColor = .label

        let done = UIButton(type: .system)
        done.configuration = doneConfig()
        done.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [title, UIView(), done])
        header.alignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .always
        content.axis = .vertical
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(header)
        view.addSubview(scrollView)
        scrollView.addSubview(content)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -40),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        configureLanguageButton(youButton)
        configureLanguageButton(themButton)

        let languageCard = addSection("Languages")
        languageCard.addArrangedSubview(row(icon: "person.fill", tint: brand, "You speak", control: youButton))
        languageCard.addArrangedSubview(divider())
        languageCard.addArrangedSubview(row(icon: "globe", tint: .systemGreen, "They speak", control: themButton))
        languageCard.addArrangedSubview(divider())
        languageCard.addArrangedSubview(row(icon: "location.fill", tint: .systemTeal, "Auto-detect from location", control: toggle(AppSettings.autoDetectLocation, #selector(autoChanged))))

        let micCard = addSection("Microphone")
        micCard.addArrangedSubview(micModeRow())
        micCard.addArrangedSubview(divider())
        micCard.addArrangedSubview(caption("Voice Isolation locks onto the closest voice and cuts background noise — best in cafés, streets, and markets. iOS only lets you switch it yourself: tap it above, or Control Center → Mic Mode.", icon: "sparkles", tint: .systemTeal))
        micCard.addArrangedSubview(divider())
        micCard.addArrangedSubview(row(icon: "bell.fill", tint: .systemPink, "Chime on their turn", control: toggle(AppSettings.turnChime, #selector(chimeChanged))))

        let displayCard = addSection("Display")
        displayCard.addArrangedSubview(row(icon: "sun.max.fill", tint: .systemOrange, "Keep screen bright", control: toggle(AppSettings.keepScreenBright, #selector(brightChanged))))
        displayCard.addArrangedSubview(divider())
        displayCard.addArrangedSubview(row(icon: "circle.lefthalf.filled", tint: .systemGray, "Appearance", control: appearanceControl()))

        minutesLabel.text = "…"
        minutesLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        minutesLabel.textColor = .secondaryLabel
        let buyButton = UIButton(type: .system)
        buyButton.setTitle("Buy minutes", for: .normal)
        buyButton.contentHorizontalAlignment = .leading
        buyButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        buyButton.tintColor = brand
        buyButton.addTarget(self, action: #selector(openStore), for: .touchUpInside)
        let minutesCard = addSection("Minutes")
        minutesCard.addArrangedSubview(row(icon: "waveform", tint: .systemPurple, "Minutes remaining", control: minutesLabel))
        minutesCard.addArrangedSubview(divider())
        minutesCard.addArrangedSubview(row(icon: "creditcard.fill", tint: brand, control: buyButton))

        let privacyCard = addSection("Privacy")
        let privacy = UILabel()
        privacy.numberOfLines = 0
        privacy.font = .systemFont(ofSize: 13)
        privacy.textColor = .secondaryLabel
        privacy.text = String(localized: "Your conversation audio is streamed directly to OpenAI to translate it, then spoken back — it never passes through our servers. See our Privacy Policy for how OpenAI handles it. Your transcript stays on this device.")
        privacyCard.addArrangedSubview(row(icon: "lock.fill", tint: .systemGreen, control: privacy))
        privacyCard.addArrangedSubview(divider())
        privacyCard.addArrangedSubview(row(icon: "doc.text.fill", tint: .systemBlue,
            control: linkButton(String(localized: "Privacy Policy"), color: brand, #selector(openPrivacyPolicy))))
        privacyCard.addArrangedSubview(divider())
        privacyCard.addArrangedSubview(row(icon: "xmark.shield.fill", tint: .systemRed,
            control: linkButton(String(localized: "Withdraw cloud AI consent"), color: .systemRed, #selector(revokeConsent))))

        let accountCard = addSection("Account")
        accountCard.addArrangedSubview(row(icon: "trash.fill", tint: .systemRed,
            control: linkButton(String(localized: "Delete Account"), color: .systemRed, #selector(confirmDeleteAccount))))
        accountCard.addArrangedSubview(divider())
        accountCard.addArrangedSubview(caption(String(localized: "Permanently deletes your account and remaining minutes from our servers, and erases on-device data. This can't be undone."), icon: "exclamationmark.triangle.fill", tint: .systemOrange))

        let moreCard = addSection("More")
        moreCard.addArrangedSubview(row(icon: "square.stack.3d.up.fill", tint: brand,
            control: linkButton(String(localized: "More Apps"), color: brand, #selector(openMoreApps))))

        let footer = UILabel()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        footer.text = "Psybeam \(version) (\(build))"
        footer.font = .systemFont(ofSize: 12)
        footer.textColor = .tertiaryLabel
        footer.textAlignment = .center
        content.addArrangedSubview(spacer(16))
        content.addArrangedSubview(footer)
    }

    private func doneConfig() -> UIButton.Configuration {
        var config = UIButton.Configuration.gray()
        config.cornerStyle = .capsule
        config.baseForegroundColor = .label
        config.attributedTitle = AttributedString("Done", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 16, weight: .semibold)]))
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16)
        return config
    }

    @discardableResult
    private func addSection(_ title: String) -> UIStackView {
        let header = UILabel()
        header.text = title.uppercased()
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        header.textColor = .secondaryLabel
        let headerWrap = UIView()
        headerWrap.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: headerWrap.topAnchor, constant: 12),
            header.bottomAnchor.constraint(equalTo: headerWrap.bottomAnchor, constant: -6),
            header.leadingAnchor.constraint(equalTo: headerWrap.leadingAnchor, constant: 16),
        ])
        content.addArrangedSubview(headerWrap)

        let card = UIVisualEffectView()
        if #available(iOS 26.0, *) {
            card.effect = UIGlassEffect()
        } else {
            card.effect = UIBlurEffect(style: .systemThinMaterial)
        }
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true

        let body = UIStackView()
        body.axis = .vertical
        body.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(body)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            body.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
        ])
        content.addArrangedSubview(card)
        return body
    }

    private func iconTile(_ symbol: String, _ tint: UIColor) -> UIView {
        let tile = UIView()
        tile.backgroundColor = tint
        tile.layer.cornerRadius = 7
        tile.layer.cornerCurve = .continuous
        tile.translatesAutoresizingMaskIntoConstraints = false
        let glyph = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)))
        glyph.tintColor = tint == UIColor.label ? .systemBackground : .white
        glyph.contentMode = .center
        glyph.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(glyph)
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 29),
            tile.heightAnchor.constraint(equalToConstant: 29),
            glyph.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
        ])
        return tile
    }

    private func row(icon: String? = nil, tint: UIColor = .systemGray, _ title: String? = nil, control: UIView) -> UIView {
        var views: [UIView] = []
        if let icon { views.append(iconTile(icon, tint)) }
        if let title {
            let label = UILabel()
            label.text = title
            label.font = .systemFont(ofSize: 16)
            label.textColor = .label
            label.numberOfLines = 0
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            views.append(label)
        }
        views.append(UIView())
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        views.append(control)
        let stack = UIStackView(arrangedSubviews: views)
        stack.alignment = .center
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        return stack
    }

    private func divider() -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        let wrap = UIStackView(arrangedSubviews: [line])
        wrap.isLayoutMarginsRelativeArrangement = true
        wrap.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 57, bottom: 0, trailing: 0)
        return wrap
    }

    private func spacer(_ height: CGFloat) -> UIView {
        let v = UIView()
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }

    private func toggle(_ on: Bool, _ action: Selector) -> UISwitch {
        let s = UISwitch()
        s.isOn = on
        s.onTintColor = brand
        s.addTarget(self, action: action, for: .valueChanged)
        return s
    }

    private func linkButton(_ title: String, color: UIColor, _ action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.tintColor = color
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func appearanceControl() -> UISegmentedControl {
        let control = UISegmentedControl(items: ["Auto", "Light", "Dark"])
        control.selectedSegmentIndex = AppSettings.appearance.rawValue
        control.selectedSegmentTintColor = brand
        control.setTitleTextAttributes([.foregroundColor: UIColor.label], for: .normal)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        control.addTarget(self, action: #selector(appearanceChanged), for: .valueChanged)
        control.setContentHuggingPriority(.required, for: .horizontal)
        return control
    }

    private func configureLanguageButton(_ button: UIButton) {
        button.showsMenuAsPrimaryAction = true
        button.tintColor = .tertiaryLabel
        var config = UIButton.Configuration.plain()
        config.imagePlacement = .trailing
        config.imagePadding = 4
        config.image = UIImage(systemName: "chevron.up.chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        config.contentInsets = .zero
        button.configuration = config
    }

    private func refreshLanguageButtons() {
        setLanguageTitle(youButton, code: viewModel.pair.traveler)
        setLanguageTitle(themButton, code: viewModel.pair.local)
        youButton.menu = languageMenu(selected: viewModel.pair.traveler, isTraveler: true)
        themButton.menu = languageMenu(selected: viewModel.pair.local, isTraveler: false)
    }

    private func setLanguageTitle(_ button: UIButton, code: String) {
        button.configuration?.attributedTitle = AttributedString(
            Self.endonym(code),
            attributes: AttributeContainer([
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor.label,
            ])
        )
    }

    private func languageMenu(selected: String, isTraveler: Bool) -> UIMenu {
        let actions = languages.map { code in
            UIAction(title: Self.endonym(code), state: code == selected ? .on : .off) { [weak self] _ in
                if isTraveler { self?.viewModel.setTravelerLanguage(code) } else { self?.viewModel.setLocalLanguage(code) }
                self?.refreshLanguageButtons()
            }
        }
        return UIMenu(children: actions)
    }

    /// Keep the minutes label live: the credit store sheet (and in-session
    /// billing) mutate the shared store's balance while this screen stays
    /// presented, and dismissing a sheet doesn't re-fire `viewDidAppear` on the
    /// presenter — so bind to the published balance instead of only sampling it
    /// on appear. `@Published` emits the current value on subscribe, so the
    /// label is set immediately.
    private func observeBalance() {
        AICreditsManager.store.$balance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] balance in self?.minutesLabel.text = "\(balance) min" }
            .store(in: &cancellables)
    }

    private func fetchBalance() {
        Task { await AICreditsManager.store.refresh() }
    }

    @objc private func openStore() {
        impact.impactOccurred()
        let store = AICreditsManager.store
        let host = UIHostingController(rootView: CreditStoreView().environmentObject(store))
        Task { await store.loadCatalog() }
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(host, animated: true)
    }

    private func micModeRow() -> UIView {
        micModeValue.font = .systemFont(ofSize: 16, weight: .semibold)
        micModeValue.textColor = .secondaryLabel
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)))
        chevron.tintColor = .tertiaryLabel
        let trailing = UIStackView(arrangedSubviews: [micModeValue, chevron])
        trailing.spacing = 5
        trailing.alignment = .center
        let r = row(icon: "waveform", tint: brand, "Voice Isolation", control: trailing)
        r.isUserInteractionEnabled = true
        r.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openMicModes)))
        return r
    }

    private func caption(_ text: String, icon: String, tint: UIColor) -> UIView {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [iconTile(icon, tint), label])
        stack.alignment = .top
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16)
        return stack
    }

    private func refreshMicMode() {
        micModeValue.text = Self.micModeName(AVCaptureDevice.activeMicrophoneMode)
    }

    private static func micModeName(_ mode: AVCaptureDevice.MicrophoneMode) -> String {
        switch mode {
        case .voiceIsolation: "Voice Isolation"
        case .wideSpectrum: "Wide Spectrum"
        case .standard: "Standard"
        @unknown default: "Standard"
        }
    }

    @objc private func openMicModes() {
        impact.impactOccurred()
        AVCaptureDevice.showSystemUserInterface(.microphoneModes)
    }

    @objc private func autoChanged(_ sender: UISwitch) { impact.impactOccurred(); AppSettings.autoDetectLocation = sender.isOn }
    @objc private func brightChanged(_ sender: UISwitch) { impact.impactOccurred(); AppSettings.keepScreenBright = sender.isOn; onBrightnessChanged() }
    @objc private func chimeChanged(_ sender: UISwitch) { impact.impactOccurred(); AppSettings.turnChime = sender.isOn }

    @objc private func appearanceChanged(_ sender: UISegmentedControl) {
        let mode = AppearanceMode(rawValue: sender.selectedSegmentIndex) ?? .system
        AppSettings.appearance = mode
        impact.impactOccurred()
        UIView.animate(withDuration: 0.3) {
            self.view.window?.overrideUserInterfaceStyle = UIUserInterfaceStyle(rawValue: mode.rawValue) ?? .unspecified
        }
    }

    @objc private func revokeConsent() {
        impact.impactOccurred()
        AppSettings.aiConsentGranted = false
        viewModel.end()
        dismiss(animated: true)
    }

    @objc private func openPrivacyPolicy() {
        impact.impactOccurred()
        UIApplication.shared.open(Links.privacyPolicy)
    }

    @objc private func openMoreApps() {
        impact.impactOccurred()
        Midgar.present(from: self)
    }

    @objc private func confirmDeleteAccount() {
        impact.impactOccurred()
        let alert = UIAlertController(
            title: String(localized: "Delete Account?"),
            message: String(localized: "This permanently deletes your account and any remaining minutes from our servers and erases on-device data. This can’t be undone."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Delete Account"), style: .destructive) { [weak self] _ in
            self?.performDeleteAccount()
        })
        present(alert, animated: true)
    }

    private func performDeleteAccount() {
        let progress = UIAlertController(title: nil, message: String(localized: "Deleting…"), preferredStyle: .alert)
        present(progress, animated: true)
        Task { @MainActor in
            do {
                try await AccountService().deleteAccount()
                self.wipeLocalData()
                self.viewModel.end()
                await AICreditsManager.store.bootstrap()
                progress.dismiss(animated: true) { self.showAccountDeleted() }
            } catch {
                progress.dismiss(animated: true) { self.showDeletionFailed() }
            }
        }
    }

    private func wipeLocalData() {
        AppSettings.aiConsentGranted = false
        AppSettings.pendingSessionId = nil
        AppSettings.pendingReservedMinutes = 0
        try? DatabaseManager.shared.wipe()
    }

    private func showAccountDeleted() {
        let alert = UIAlertController(
            title: String(localized: "Account Deleted"),
            message: String(localized: "Your account and data have been removed."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { [weak self] _ in
            self?.dismiss(animated: true) { self?.onDismiss?() }
        })
        present(alert, animated: true)
    }

    private func showDeletionFailed() {
        let alert = UIAlertController(
            title: String(localized: "Couldn’t Delete Account"),
            message: String(localized: "Please check your connection and try again."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    @objc private func dismissSelf() { dismiss(animated: true) }

    private static func endonym(_ code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }
}
