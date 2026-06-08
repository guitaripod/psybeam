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
        title.text = String(localized: "Cloud translation")
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textColor = .label
        title.textAlignment = .center
        title.numberOfLines = 0

        let body = UILabel()
        body.text = String(localized: "Psybeam translates speech using AI in the cloud. To translate, your spoken audio is sent to a secure cloud service and isn’t stored there.\n\nYour conversation transcript stays on this device — we never keep it on our servers. The person you speak with is also translated by cloud AI.")
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

        let buttons = UIStackView(arrangedSubviews: [agree, decline, footnote])
        buttons.axis = .vertical
        buttons.alignment = .fill
        buttons.spacing = 6
        buttons.setCustomSpacing(18, after: decline)
        buttons.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        view.addSubview(buttons)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -36),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            buttons.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }
}
