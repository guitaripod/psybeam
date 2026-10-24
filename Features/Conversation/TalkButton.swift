import UIKit

final class TalkButton: UIVisualEffectView {
    let languageLabel = UILabel()
    private let icon = UIImageView()
    private let hintLabel = UILabel()
    private let accent: UIColor
    private var isActive = false
    private var isBeckoning = false
    private var pressAccepted = false

    /// Asked on touch-down; returning false (no consent yet, mic denied) keeps
    /// the button at rest instead of lighting it up for a hold that never started.
    var onPress: (() -> Bool)?
    var onRelease: (() -> Void)?

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
        isExclusiveTouch = true
        isMultipleTouchEnabled = false

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setActive(_ active: Bool) {
        isActive = active
        icon.removeAllSymbolEffects()
        layer.removeAnimation(forKey: Self.beckonKey)
        if active {
            icon.addSymbolEffect(.pulse, options: .repeat(.continuous))
        } else {
            startBeckonIfNeeded()
        }
        UIView.animate(withDuration: 0.18, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4) {
            self.transform = active ? CGAffineTransform(scaleX: 1.06, y: 1.06) : .identity
            self.layer.borderColor = self.accent.withAlphaComponent(active ? 1.0 : 0.55).cgColor
            self.layer.borderWidth = active ? 3 : 2
        }
    }

    /// The first-run coach's pointer: a slow breathing glow that says "this
    /// one" without looking like a live hold. Paused while the button is held.
    func setBeckoning(_ beckoning: Bool) {
        guard beckoning != isBeckoning else { return }
        isBeckoning = beckoning
        guard !isActive else { return }
        icon.removeAllSymbolEffects()
        layer.removeAnimation(forKey: Self.beckonKey)
        startBeckonIfNeeded()
    }

    private static let beckonKey = "psybeam.beckon"

    private func startBeckonIfNeeded() {
        guard isBeckoning else { return }
        icon.addSymbolEffect(.breathe, options: .repeat(.continuous))
        let glow = CABasicAnimation(keyPath: "borderColor")
        glow.fromValue = accent.withAlphaComponent(0.55).cgColor
        glow.toValue = accent.cgColor
        glow.duration = 0.9
        glow.autoreverses = true
        glow.repeatCount = .infinity
        glow.isRemovedOnCompletion = false
        glow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(glow, forKey: Self.beckonKey)
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            pressAccepted = onPress?() ?? false
            if pressAccepted { setActive(true) }
        case .ended, .cancelled, .failed:
            guard pressAccepted else { return }
            pressAccepted = false
            setActive(false)
            onRelease?()
        default:
            break
        }
    }
}
