import PsybeamKit
import UIKit

extension ConversationViewController {
    /// A flat translucent pill, deliberately NOT a glass effect view: live glass
    /// over the 60fps Metal aurora re-samples the moving colours every frame —
    /// which tinted the bar with shifting hues (worst on cold launch) and cost a
    /// full blur pass per frame. A solid host is also immune to the menu-morph
    /// snapshot that broke the corner radius.
    func configureLanguageBar() {
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
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
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

    func makeLangMenu(isTraveler: Bool) -> UIMenu {
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
    func chooseLanguage(_ code: String, isTraveler: Bool) {
        let before = viewModel.pair
        if isTraveler { viewModel.setTravelerLanguage(code) } else { viewModel.setLocalLanguage(code) }
        if viewModel.pair != before { setFirstRun(.done) }
    }

    func setLangButtonTitle(_ button: UIButton, _ text: String, _ color: UIColor) {
        button.configuration?.attributedTitle = AttributedString(text, attributes: AttributeContainer([
            .font: UIFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: color,
        ]))
    }

    @objc func swapLanguages() {
        impact.impactOccurred()
        viewModel.swapLanguages()
        setFirstRun(.done)
    }

    func configureLabels() {
        statusLabel.font = .systemFont(ofSize: 14, weight: .heavy)
        statusLabel.textColor = .clear
        statusLabel.textAlignment = .center
        statusLabel.setContentHuggingPriority(.required, for: .vertical)

        translatedLabel.font = captionFont
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
    func configureConsentButton() {
        styleResolveButton(consentButton, title: String(localized: "Review consent"), symbol: "cloud.fill")
        consentButton.addAction(UIAction { [weak self] _ in self?.presentConsent() }, for: .touchUpInside)
    }

    /// The way out of a denied microphone: the caption says why nothing
    /// happens, and this opens the app's page in Settings.
    func configureMicSettingsButton() {
        styleResolveButton(micSettingsButton, title: String(localized: "Open Settings"), symbol: "gearshape.fill")
        micSettingsButton.addTarget(self, action: #selector(openAppSettings), for: .touchUpInside)
    }

    func configureNoticeButton() {
        noticeButton.translatesAutoresizingMaskIntoConstraints = false
        noticeButton.alpha = 0
        noticeButton.isUserInteractionEnabled = false
        noticeButton.addAction(UIAction { [weak self] _ in self?.presentStoreIfPossible() }, for: .touchUpInside)
    }

    func styleResolveButton(_ button: UIButton, title: String, symbol: String) {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = brand
        config.baseForegroundColor = .white
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        config.imagePadding = 8
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 17, weight: .semibold), maximumPointSize: 26),
        ]))
        config.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 22, bottom: 13, trailing: 22)
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
    }

    func configureTalkButtons() {
        meButton.onPress = { [weak self] in self?.pressBegan(.traveler) ?? false }
        meButton.onRelease = { [weak self] in self?.pressEnded(.traveler) }
        themButton.onPress = { [weak self] in self?.pressBegan(.local) ?? false }
        themButton.onRelease = { [weak self] in self?.pressEnded(.local) }
    }

    /// The honest-floor indicator for the bystander who can't consent to cloud
    /// routing: a persistent, neutral (not blue/green) "cloud AI" mark. Never
    /// claims on-device.
    func configureCloudBadge() {
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

    func configureGearButton() {
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
}
