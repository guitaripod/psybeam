import UIKit

final class TalkButton: UIVisualEffectView {
    let languageLabel = UILabel()
    private let icon = UIImageView()
    private let hintLabel = UILabel()
    private let accent: UIColor
    var onHold: ((Bool) -> Void)?

    init(accent: UIColor, hint: String, micSymbol: String) {
        self.accent = accent
        super.init(effect: nil)
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = true
            effect = glass
        } else {
            effect = UIBlurEffect(style: .systemThinMaterialDark)
        }
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        clipsToBounds = true
        layer.borderWidth = 2
        layer.borderColor = accent.withAlphaComponent(0.55).cgColor

        icon.image = UIImage(systemName: micSymbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold))
        icon.tintColor = accent
        icon.contentMode = .center

        languageLabel.font = .systemFont(ofSize: 21, weight: .bold)
        languageLabel.textColor = .white
        languageLabel.textAlignment = .center
        languageLabel.adjustsFontSizeToFitWidth = true
        languageLabel.minimumScaleFactor = 0.6

        hintLabel.text = hint
        hintLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        hintLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [icon, languageLabel, hintLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8),
        ])

        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0
        addGestureRecognizer(press)

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setActive(_ active: Bool) {
        if active {
            icon.addSymbolEffect(.pulse, options: .repeat(.continuous))
        } else {
            icon.removeAllSymbolEffects()
        }
        UIView.animate(withDuration: 0.18, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4) {
            self.transform = active ? CGAffineTransform(scaleX: 1.06, y: 1.06) : .identity
            self.layer.borderColor = self.accent.withAlphaComponent(active ? 1.0 : 0.55).cgColor
            self.layer.borderWidth = active ? 3 : 2
        }
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            setActive(true)
            onHold?(true)
        case .ended, .cancelled, .failed:
            setActive(false)
            onHold?(false)
        default:
            break
        }
    }
}
