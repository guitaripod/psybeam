import UIKit

/// The pre-audio third-party-AI consent gate (App Review 5.1.2(i)). Shown before
/// any session is opened to OpenAI; consent is persisted and revocable in Settings.
final class ConsentViewController: UIViewController {
    var onAgree: (() -> Void)?
    var onDecline: (() -> Void)?

    private let brand = UIColor(red: 0.30, green: 0.62, blue: 1.0, alpha: 1)

    override var preferredStatusBarStyle: UIStatusBarStyle {
        traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        build()
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let icon = UIImageView(image: UIImage(systemName: "cloud", withConfiguration: UIImage.SymbolConfiguration(pointSize: 50, weight: .semibold)))
        icon.tintColor = brand
        icon.contentMode = .center

        let title = UILabel()
        title.text = String(localized: "Translation by OpenAI")
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textColor = .label
        title.textAlignment = .center
        title.numberOfLines = 0

        let body = UILabel()
        body.text = String(localized: "To translate, the microphone audio of your conversation is streamed in real time to OpenAI — our cloud translation provider — and the translation is spoken back to you. OpenAI processes the audio only to translate it; it isn’t stored on our servers and isn’t used to train AI models.\n\nYour conversation transcript stays on this device. The person you speak with is translated by OpenAI the same way.")
        body.font = .systemFont(ofSize: 16)
        body.textColor = .secondaryLabel
        body.numberOfLines = 0
        body.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [icon, title, body])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.setCustomSpacing(24, after: icon)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let agree = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .large
        config.baseBackgroundColor = brand
        config.baseForegroundColor = .white
        config.attributedTitle = AttributedString(String(localized: "Agree & Continue"), attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
        config.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 20, bottom: 15, trailing: 20)
        agree.configuration = config
        agree.addAction(UIAction { [weak self] _ in self?.onAgree?() }, for: .touchUpInside)

        let decline = UIButton(type: .system)
        decline.setTitle(String(localized: "Not now"), for: .normal)
        decline.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        decline.tintColor = .secondaryLabel
        decline.addAction(UIAction { [weak self] _ in self?.onDecline?() }, for: .touchUpInside)

        let footnote = UILabel()
        footnote.text = String(localized: "You can withdraw consent anytime in Settings.")
        footnote.font = .systemFont(ofSize: 13)
        footnote.textColor = .tertiaryLabel
        footnote.textAlignment = .center
        footnote.numberOfLines = 0

        let privacyLink = UIButton(type: .system)
        privacyLink.setTitle(String(localized: "Privacy Policy"), for: .normal)
        privacyLink.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        privacyLink.tintColor = brand
        privacyLink.addAction(UIAction { _ in UIApplication.shared.open(Links.privacyPolicy) }, for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [agree, decline, footnote, privacyLink])
        buttons.axis = .vertical
        buttons.alignment = .fill
        buttons.spacing = 6
        buttons.setCustomSpacing(18, after: decline)
        buttons.setCustomSpacing(2, after: footnote)
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true

        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        scrollView.addSubview(content)
        view.addSubview(scrollView)
        view.addSubview(buttons)

        // Center the disclosure when it fits; scroll it when it doesn't — so a
        // long disclosure can never be cropped on a short window (e.g. an iPad
        // running the iPhone app, landscape, or large Dynamic Type). The buttons
        // stay pinned to the bottom so the call to action is always reachable.
        let fitViewport = content.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        fitViewport.priority = .defaultLow

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            fitViewport,

            stack.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),

            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            buttons.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }
}
