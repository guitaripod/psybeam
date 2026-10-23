import AVFoundation
import MidgarUI
import PsybeamKit
import SwiftUI
import UIKit
import AICreditsUI

extension SettingsViewController {
    func makeSections() -> [MidgarSettingsSection] {
        [
            MidgarSettingsSection(id: "languages", title: String(localized: "Languages"), rows: languageRows()),
            MidgarSettingsSection(
                id: "microphone", title: String(localized: "Microphone"),
                footer: String(localized: "Voice Isolation locks onto the closest voice and cuts background noise — best in cafés, streets, and markets. iOS only lets you switch it yourself: tap it above, or Control Center → Mic Mode."),
                rows: microphoneRows()),
            MidgarSettingsSection(id: "display", title: String(localized: "Display"), rows: displayRows()),
            MidgarSettingsSection(id: "minutes", title: String(localized: "Minutes"), rows: minutesRows()),
            MidgarSettingsSection(
                id: "privacy", title: String(localized: "Privacy"),
                footer: String(localized: "Your conversation audio is streamed directly to OpenAI to translate it, then spoken back — it never passes through our servers. See our Privacy Policy for how OpenAI handles it. Your transcript stays on this device."),
                rows: privacyRows()),
            MidgarSettingsSection(
                id: "account", title: String(localized: "Account"),
                footer: String(localized: "Permanently deletes your account and remaining minutes from our servers, and erases on-device data. This can't be undone."),
                rows: [deleteAccountRow()]),
            MidgarSettingsSection(id: "more", title: String(localized: "More"), rows: moreRows()),
        ]
    }

    private func languageRows() -> [MidgarSettingsRow] {
        let you = MidgarSettingsRow.custom(
            id: "you", title: String(localized: "You speak"), detail: LanguageNames.endonym(viewModel.pair.traveler),
            systemImage: "person.fill"
        ) { [weak self] in self?.pickLanguage(isTraveler: true) }
        let them = MidgarSettingsRow.custom(
            id: "them", title: String(localized: "They speak"), detail: LanguageNames.endonym(viewModel.pair.local),
            systemImage: "globe"
        ) { [weak self] in self?.pickLanguage(isTraveler: false) }
        let autoDetect = MidgarSettingsRow.toggle(
            id: "autoDetect", title: String(localized: "Auto-detect from location"), systemImage: "location.fill",
            isOn: { AppSettings.autoDetectLocation },
            setOn: { [weak self] isOn in
                AppSettings.autoDetectLocation = isOn
                if isOn { self?.onAutoDetectEnabled() }
            })
        return [you, them, autoDetect]
    }

    private func microphoneRows() -> [MidgarSettingsRow] {
        let voiceIsolation = MidgarSettingsRow.custom(
            id: "voiceIsolation", title: String(localized: "Voice Isolation"), detail: Self.currentMicModeName(),
            systemImage: "waveform"
        ) { AVCaptureDevice.showSystemUserInterface(.microphoneModes) }
        let chime = MidgarSettingsRow.toggle(
            id: "chime", title: String(localized: "Chime on their turn"), systemImage: "bell.fill",
            isOn: { AppSettings.turnChime },
            setOn: { AppSettings.turnChime = $0 })
        return [voiceIsolation, chime]
    }

    private func displayRows() -> [MidgarSettingsRow] {
        let bright = MidgarSettingsRow.toggle(
            id: "bright", title: String(localized: "Keep screen bright"), systemImage: "sun.max.fill",
            isOn: { AppSettings.keepScreenBright },
            setOn: { [weak self] isOn in
                AppSettings.keepScreenBright = isOn
                self?.onBrightnessChanged()
            })
        let appearance = MidgarSettingsRow.custom(
            id: "appearance", title: String(localized: "Appearance"), detail: AppSettings.appearance.title,
            systemImage: "circle.lefthalf.filled"
        ) { [weak self] in self?.chooseAppearance() }
        return [bright, appearance]
    }

    private func minutesRows() -> [MidgarSettingsRow] {
        let remaining = MidgarSettingsRow.info(
            id: "minutes", title: String(localized: "Minutes remaining"), detail: minutesDetail(),
            systemImage: "waveform")
        let buy = MidgarSettingsRow.custom(
            id: "buy", title: String(localized: "Buy minutes"), systemImage: "creditcard.fill"
        ) { [weak self] in self?.openStore() }
        return [remaining, buy]
    }

    private func minutesDetail() -> String {
        #if DEBUG
        if isDemoLaunch { return String(localized: "\(DemoConfiguration.freeMinutesGrant) min") }
        #endif
        return String(localized: "\(AICreditsManager.store.balance) min")
    }

    private func privacyRows() -> [MidgarSettingsRow] {
        let withdraw = MidgarSettingsRow(
            id: "withdrawConsent", title: String(localized: "Withdraw cloud AI consent"),
            systemImage: "xmark.shield.fill", role: .destructive,
            kind: .action { [weak self] in self?.revokeConsent() })
        return [.privacyPolicy(url: Links.privacyPolicy), withdraw]
    }

    private func deleteAccountRow() -> MidgarSettingsRow {
        .deleteAccount(
            confirmation: MidgarSettingsRow.Confirmation(
                title: String(localized: "Delete Account?"),
                message: String(localized: "This permanently deletes your account and any remaining minutes from our servers and erases on-device data. This can’t be undone."),
                confirmTitle: String(localized: "Delete Account"))
        ) { [weak self] in
            guard let self else { return }
            try await deleteAccount()
        }
    }

    private func moreRows() -> [MidgarSettingsRow] {
        let share = MidgarSettingsRow.custom(
            id: "share", title: String(localized: "Share Psybeam"), systemImage: "square.and.arrow.up.fill",
            showsDisclosure: false
        ) { [weak self] in self?.sharePsybeam() }
        let rate = MidgarSettingsRow.link(
            id: "rate", title: String(localized: "Rate Psybeam"), systemImage: "star.fill", url: Links.writeReview)
        return [share, rate, .version()]
    }

    private func pickLanguage(isTraveler: Bool) {
        let pair = viewModel.pair
        let options = SupportedLanguages.codes.map {
            OptionPickerViewController.Option(id: $0, title: LanguageNames.endonym($0))
        }
        let picker = OptionPickerViewController(
            title: isTraveler ? String(localized: "You speak") : String(localized: "They speak"),
            options: options,
            selectedID: isTraveler ? pair.traveler : pair.local
        ) { [weak self] code in
            guard let self else { return }
            if isTraveler { viewModel.setTravelerLanguage(code) } else { viewModel.setLocalLanguage(code) }
            refreshList()
        }
        pushViewController(picker, animated: true)
    }

    private func chooseAppearance() {
        let options = AppearanceMode.allCases.map {
            OptionPickerViewController.Option(id: String($0.rawValue), title: $0.title)
        }
        let picker = OptionPickerViewController(
            title: String(localized: "Appearance"),
            options: options,
            selectedID: String(AppSettings.appearance.rawValue)
        ) { [weak self] id in
            guard let self, let raw = Int(id), let mode = AppearanceMode(rawValue: raw) else { return }
            apply(mode)
        }
        pushViewController(picker, animated: true)
    }

    private func apply(_ mode: AppearanceMode) {
        AppSettings.appearance = mode
        UIView.animate(withDuration: 0.3) {
            self.view.window?.overrideUserInterfaceStyle = UIUserInterfaceStyle(rawValue: mode.rawValue) ?? .unspecified
        }
        refreshList()
    }

    private func openStore() {
        let store = AICreditsManager.store
        let host = UIHostingController(rootView: CreditStoreView().environmentObject(store))
        Task { await store.loadCatalog() }
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(host, animated: true)
    }

    private func revokeConsent() {
        AppSettings.aiConsentGranted = false
        viewModel.end()
        dismiss(animated: true)
    }

    /// The share sheet gets the text and the URL as separate items so Messages and Mail render
    /// a rich App Store link card instead of a bare URL buried in a sentence.
    private func sharePsybeam() {
        let pitch = String(localized: "Talk to anyone in their language. Psybeam translates voice to voice while you travel.")
        let sheet = UIActivityViewController(activityItems: [pitch, Links.appStore], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        present(sheet, animated: true)
    }
}

extension AppearanceMode {
    var title: String {
        switch self {
        case .system: String(localized: "Auto")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}
