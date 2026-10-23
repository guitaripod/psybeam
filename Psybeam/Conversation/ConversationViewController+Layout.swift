import PsybeamKit
import UIKit

extension ConversationViewController {
    func layoutVisualizer() {
        visualizer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(visualizer)
        NSLayoutConstraint.activate([
            visualizer.topAnchor.constraint(equalTo: view.topAnchor),
            visualizer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            visualizer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            visualizer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func layoutConvo() {
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
        configureMicSettingsButton()
        configureNoticeButton()
        applyFlip(animated: false)

        buttonRow.addArrangedSubview(meButton)
        buttonRow.addArrangedSubview(themButton)
        buttonRow.axis = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 14
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        [statusLabel, promptLabel, translatedLabel, sourceLabel, consentButton, micSettingsButton, noticeButton, coachLabel, buttonRow, gearGlass, languageBarHost, cloudBadge]
            .forEach { convoRoot.addSubview($0) }
        convoRoot.addLayoutGuide(captionColumn)
        convoRoot.addLayoutGuide(controlColumn)

        NSLayoutConstraint.activate(
            columnConstraints() + captionConstraints() + controlConstraints() + topBarConstraints() + stackedConstraints)
    }

    /// The two zones' horizontal extents. Their constants are the only thing a
    /// layout plan changes, so every label and button hangs off these guides.
    /// They hang off the left edge, not the leading one: the plan's numbers are
    /// physical, because the bar and the fold do not mirror in a right-to-left
    /// language.
    func columnConstraints() -> [NSLayoutConstraint] {
        [
            captionColumnConstraints.0, captionColumnConstraints.1,
            controlColumnConstraints.0, controlColumnConstraints.1,
        ]
    }

    func captionConstraints() -> [NSLayoutConstraint] {
        [
            translatedLabel.leadingAnchor.constraint(equalTo: captionColumn.leadingAnchor),
            translatedLabel.trailingAnchor.constraint(equalTo: captionColumn.trailingAnchor),
            captionCenter,
            promptCenter,

            statusLabel.bottomAnchor.constraint(equalTo: translatedLabel.topAnchor, constant: -22),
            statusLabel.centerXAnchor.constraint(equalTo: captionColumn.centerXAnchor),

            sourceLabel.topAnchor.constraint(equalTo: translatedLabel.bottomAnchor, constant: 16),
            sourceLabel.leadingAnchor.constraint(equalTo: captionColumn.leadingAnchor),
            sourceLabel.trailingAnchor.constraint(equalTo: captionColumn.trailingAnchor),

            consentButton.topAnchor.constraint(equalTo: translatedLabel.bottomAnchor, constant: 28),
            consentButton.centerXAnchor.constraint(equalTo: captionColumn.centerXAnchor),
            consentButton.leadingAnchor.constraint(greaterThanOrEqualTo: captionColumn.leadingAnchor),
            consentButton.trailingAnchor.constraint(lessThanOrEqualTo: captionColumn.trailingAnchor),

            micSettingsButton.topAnchor.constraint(equalTo: translatedLabel.bottomAnchor, constant: 28),
            micSettingsButton.centerXAnchor.constraint(equalTo: captionColumn.centerXAnchor),
            micSettingsButton.leadingAnchor.constraint(greaterThanOrEqualTo: captionColumn.leadingAnchor),
            micSettingsButton.trailingAnchor.constraint(lessThanOrEqualTo: captionColumn.trailingAnchor),

            promptLabel.leadingAnchor.constraint(equalTo: captionColumn.leadingAnchor),
            promptLabel.trailingAnchor.constraint(equalTo: captionColumn.trailingAnchor),

            coachLabel.leadingAnchor.constraint(equalTo: captionColumn.leadingAnchor),
            coachLabel.trailingAnchor.constraint(equalTo: captionColumn.trailingAnchor),
            coachLabel.topAnchor.constraint(greaterThanOrEqualTo: sourceLabel.bottomAnchor, constant: 12),
        ]
    }

    func controlConstraints() -> [NSLayoutConstraint] {
        [
            buttonRow.leadingAnchor.constraint(equalTo: controlColumn.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: controlColumn.trailingAnchor),
            buttonRowHeight,
            cloudBadge.centerXAnchor.constraint(equalTo: controlColumn.centerXAnchor),
        ]
    }

    func topBarConstraints() -> [NSLayoutConstraint] {
        let safe = convoRoot.safeAreaLayoutGuide
        return [
            noticeButton.topAnchor.constraint(equalTo: gearGlass.bottomAnchor, constant: 12),
            noticeButton.centerXAnchor.constraint(equalTo: captionColumn.centerXAnchor),
            noticeButton.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor, constant: 20),
            noticeButton.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -20),

            gearGlass.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            gearGlass.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            gearGlass.widthAnchor.constraint(equalToConstant: 46),
            gearGlass.heightAnchor.constraint(equalToConstant: 46),

            languageBarHost.centerYAnchor.constraint(equalTo: gearGlass.centerYAnchor),
            languageBarCenterX,
            languageBarHost.leadingAnchor.constraint(greaterThanOrEqualTo: gearGlass.trailingAnchor, constant: 8),
            languageBarHost.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -20),
            languageBarHost.heightAnchor.constraint(equalToConstant: 42),
        ]
    }

    /// The talk buttons along the bottom with the cloud badge above them, and
    /// the coach line above the badge: the phone layout.
    var stackedConstraints: [NSLayoutConstraint] {
        [stackedRowBottom, stackedBadgeBottom, stackedCoachBottom]
    }

    /// The talk buttons in a column under the language bar with the badge
    /// beneath them, and the coach line at the foot of the caption zone.
    var sideBySideConstraints: [NSLayoutConstraint] {
        [sideRowBottom, sideBadgeBottom, sideCoachBottom]
    }

    /// The caption sits just above centre, but gives way upward rather than let
    /// it and its source line run into the coach line above the buttons. That
    /// happens with a long caption on the smallest screens, including the
    /// 375×667 window an iPad runs this iPhone app in. Centring ranks just
    /// below the labels' compression resistance, so the caption moves instead
    /// of the coach line or the cloud badge being squeezed.
    func makeCaptionCenter() -> NSLayoutConstraint {
        let center = translatedLabel.centerYAnchor.constraint(equalTo: convoRoot.centerYAnchor, constant: -40)
        center.priority = .defaultHigh - 1
        return center
    }

    /// Centred when it fits, but free to slide right: centred, the room left of
    /// it ends at the gear, which on a 375pt screen is too narrow for two long
    /// language names and made them wrap.
    func makeLanguageBarCenterX() -> NSLayoutConstraint {
        let centering = languageBarHost.centerXAnchor.constraint(equalTo: convoRoot.leftAnchor)
        centering.priority = .defaultHigh - 1
        return centering
    }

    /// Re-plans on every layout pass, because the window changes size when the
    /// display or the fold does. Reserved regions can arrive a pass late, so a
    /// new size queues one more pass to read them.
    func applyLayoutPlan() {
        let size = convoRoot.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        if size != plannedSize {
            plannedSize = size
            DispatchQueue.main.async { [weak self] in self?.view.setNeedsLayout() }
        }
        let insets = convoRoot.safeAreaInsets
        let plan = ConversationLayoutPlan(
            size: size, safeInsets: insets, fold: foldRegion(), topBarBottom: insets.top + 8 + 46 + 12)
        guard plan != appliedPlan else { return }
        let previous = appliedPlan
        appliedPlan = plan
        captionColumnConstraints.0.constant = plan.captionColumn.lowerBound
        captionColumnConstraints.1.constant = plan.captionColumn.upperBound
        controlColumnConstraints.0.constant = plan.controlColumn.lowerBound
        controlColumnConstraints.1.constant = plan.controlColumn.upperBound
        languageBarCenterX.constant = plan.languageBarCenterX
        captionCenter.constant = plan.captionCenterOffset
        promptCenter.constant = plan.captionCenterOffset - Self.promptAboveCaption
        buttonRowHeight.constant = plan.buttonRowHeight
        if previous?.arrangement != plan.arrangement { applyArrangement(plan.arrangement) }
        if previous?.captionPointSize != plan.captionPointSize { captionSizeChanged() }
    }

    func applyArrangement(_ arrangement: ConversationLayoutPlan.Arrangement) {
        switch arrangement {
        case .stacked:
            NSLayoutConstraint.deactivate(sideBySideConstraints)
            NSLayoutConstraint.activate(stackedConstraints)
            buttonRow.axis = .horizontal
        case .sideBySide:
            NSLayoutConstraint.deactivate(stackedConstraints)
            NSLayoutConstraint.activate(sideBySideConstraints)
            buttonRow.axis = .vertical
        }
    }

    func captionSizeChanged() {
        if hasTranslation { translatedLabel.font = captionFont }
        refreshResting()
    }

    /// The fold, whether or not the device is bent: its frame does not change
    /// with the pose, so the layout needs no pose and no angle.
    func foldRegion() -> CGRect? {
        #if canImport(UIKit, _version: 9127.0.85)
        if #available(iOS 27.1, *) {
            return convoRoot.reservedRegions(kind: .division, options: .includeInactive).first?.frame
        }
        #endif
        return nil
    }
}
