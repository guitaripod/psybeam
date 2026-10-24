import AVFAudio
import PsybeamCore
import UIKit

extension ConversationViewController {
    func presentConsent() {
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

    func continueAfterConsent() {
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
    func presentDestinationPicker() {
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

    func finishDestination(choosing code: String?) {
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

    func beginReplayedWalkthrough() {
        if needsConsent {
            presentConsent()
        } else {
            presentDestinationPicker()
        }
    }

    /// The screen takes the new pair now rather than on the view model's next
    /// main-queue delivery, so the coach step that follows, and its VoiceOver
    /// announcement, name the language just picked.
    func applyDestination(_ code: String) {
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
    func restoreResting() {
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
    func refreshResting() {
        let showsMicSettings = !needsConsent && micDenied
        consentButton.isHidden = !needsConsent
        consentButtonClearance.isActive = needsConsent
        micSettingsButton.isHidden = !showsMicSettings
        micSettingsButtonClearance.isActive = showsMicSettings
        refreshCoach()
        guard heldSide == nil else { return }
        if showsMicSettings {
            hasTranslation = false
            sourceLabel.text = ""
            let explanation = String(localized: "Microphone access is off, so Psybeam can’t hear you. Turn it on in Settings to translate.")
            showResting(NSAttributedString(
                string: explanation, attributes: restingAttributes(size: 28, alpha: 0.85, style: .title1, maximumScale: 1.15)))
        } else if needsConsent {
            hasTranslation = false
            sourceLabel.text = ""
            let explanation = String(localized: "Psybeam needs your OK to send speech to its cloud translator.")
            showResting(NSAttributedString(
                string: explanation, attributes: restingAttributes(size: 28, alpha: 0.85, style: .title1, maximumScale: 1.15)))
        } else if !hasTranslation {
            let placeholder = NSAttributedString(
                string: String(localized: "Hold a button and speak"),
                attributes: restingAttributes(size: captionFont.pointSize, alpha: 0.55, style: .title1))
            showResting(coachText(for: firstRun, size: 28, style: .title1) ?? placeholder)
        }
    }

    func showResting(_ caption: NSAttributedString) {
        translatedLabel.attributedText = caption
        setAudience(.traveler)
    }

    /// The coach's pointers: the button to hold next breathes, and once the
    /// caption area holds a translation for them, the next step moves to a
    /// line above the buttons. Both stand down while anyone is holding and
    /// while a released turn is still settling, so the button just let go of
    /// never breathes again for the moment before its turn completes.
    func refreshCoach() {
        let idle = !needsConsent && heldSide == nil && pendingTurns.isEmpty
        let beckoning = idle ? firstRun.beckoning : nil
        meButton.setBeckoning(beckoning == .traveler)
        themButton.setBeckoning(beckoning == .local)
        let line = idle ? coachLine() : nil
        coachLabel.attributedText = line
        UIView.animate(withDuration: 0.25) { self.coachLabel.alpha = line == nil ? 0 : 1 }
    }

    /// Above the buttons: why the first hold is about to ask for the
    /// microphone, then, once the caption area holds a translation for them,
    /// the walkthrough's next step.
    func coachLine() -> NSAttributedString? {
        if showsMicrophoneReason {
            return NSAttributedString(
                string: String(localized: "Your first hold asks for the microphone. Tap Allow so Psybeam can hear you."),
                attributes: restingAttributes(size: 17, alpha: 0.82, style: .headline))
        }
        guard hasTranslation, firstRun == .holdTheirs else { return nil }
        return coachText(for: firstRun, size: 17, style: .headline)
    }

    var showsMicrophoneReason: Bool {
        !isDemo && sessionStarted && AVAudioApplication.shared.recordPermission == .undetermined
    }

    /// A coaching step's line, with each language in its button's colour. The
    /// button to hold is named as it is printed on the button; the language
    /// you'll hear is named in the UI language.
    func coachText(for stage: FirstRunStage, size: CGFloat, style: UIFont.TextStyle) -> NSAttributedString? {
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

    func highlight(
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
    func restingAttributes(
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

    func setFirstRun(_ stage: FirstRunStage) {
        guard stage != firstRun else { return }
        firstRun = stage
        if !isDemo { AppSettings.firstRunStage = stage }
        refreshResting()
        if let line = coachText(for: stage, size: 17, style: .headline)?.string {
            UIAccessibility.post(notification: .announcement, argument: line)
        }
    }

    /// Finishing the walkthrough is the first time the destination matters
    /// beyond the practice, so it is when Psybeam says what location is for
    /// and offers to use it, once. Settings' auto-detect switch is the way back.
    func scheduleLocationOffer() {
        guard !isDemo, !AppSettings.locationOffered, AppSettings.autoDetectLocation, location.isUndetermined else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.presentLocationOffer() }
    }

    func presentLocationOffer() {
        guard presentedViewController == nil, heldSide == nil, location.isUndetermined else { return }
        AppSettings.locationOffered = true
        let alert = UIAlertController(
            title: nil,
            message: String(localized: "Psybeam can pick their language from where you are. Tap Allow when iOS asks."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Not now"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Use my location"), style: .default) { [weak self] _ in
            self?.location.requestAuthorization()
        })
        present(alert, animated: true)
    }
}
