import AICreditsUI
import MidgarCore
import PsybeamKit
import SwiftUI
import UIKit

extension ConversationViewController {
    var isOnline: Bool {
        #if DEBUG
        if LaunchOverrides.current.offline { return false }
        #endif
        return NetworkMonitor.shared.isOnline
    }

    func connectivityChanged() {
        if isOnline, knownBalance == nil, sessionStarted { refreshBalance() }
        refreshNotice()
    }

    /// Reads the balance for the upfront notice. A failed read leaves the
    /// balance unknown, which shows nothing: the hold still reports the truth.
    func refreshBalance() {
        #if DEBUG
        if let forced = LaunchOverrides.current.balance {
            knownBalance = forced
            refreshNotice()
            return
        }
        #endif
        Task {
            do {
                knownBalance = try await AICreditsManager.shared.client.balance().balance
                refreshNotice()
            } catch {
                MidgarLog.notice("balance check failed: \(error)", category: .ui)
            }
        }
    }

    /// The upfront state of the session: offline, out of minutes, or running
    /// low. Users with minutes and a connection see nothing at all.
    func refreshNotice() {
        let notice = isDemo || !sessionStarted ? nil : SessionNotice.evaluate(
            isOnline: isOnline, balance: knownBalance, lowThreshold: AICreditsManager.lowBalanceThreshold)
        guard notice != shownNotice else { return }
        shownNotice = notice
        if let notice {
            MidgarLog.info("session notice \(notice)", category: .ui)
            configureNotice(notice)
        }
        UIView.animate(withDuration: 0.25) { self.noticeButton.alpha = notice == nil ? 0 : 1 }
        noticeButton.isUserInteractionEnabled = notice?.offersStore ?? false
        if let text = noticeButton.accessibilityLabel, notice != nil {
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }

    func configureNotice(_ notice: SessionNotice) {
        let (text, symbol, tint): (String, String, UIColor) = switch notice {
        case .offline:
            (String(localized: "No connection. Translation needs the internet."), "wifi.slash", amber)
        case .outOfMinutes:
            (String(localized: "You’re out of minutes. Tap to buy more."), "hourglass", errorRed)
        case .lowMinutes(let minutes):
            (String(localized: "\(minutes) minutes left. Tap to top up."), "hourglass.bottomhalf.filled", amber)
        }
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        config.imagePadding = 8
        config.imageColorTransformer = UIConfigurationColorTransformer { _ in tint }
        config.attributedTitle = AttributedString(text, attributes: AttributeContainer([
            .font: UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 14, weight: .semibold), maximumPointSize: 22),
            .foregroundColor: UIColor.white,
        ]))
        config.titleAlignment = .leading
        config.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 16)
        config.background.backgroundColor = UIColor(white: 0.05, alpha: 0.72)
        config.background.strokeColor = tint.withAlphaComponent(0.6)
        config.background.strokeWidth = 1
        config.background.cornerRadius = 18
        noticeButton.configuration = config
        noticeButton.accessibilityLabel = text
        noticeButton.accessibilityTraits = notice.offersStore ? .button : .staticText
    }

    /// On a 402 from /start (out of credits) the leg surfaces `.quotaExhausted`;
    /// present the credit store so the user can top up minutes.
    func presentStoreIfPossible() {
        guard presentedViewController == nil else { return }
        let store = AICreditsManager.store
        let host = UIHostingController(rootView: CreditStoreView().environmentObject(store))
        Task { await store.loadCatalog() }
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(host, animated: true)
    }
}
