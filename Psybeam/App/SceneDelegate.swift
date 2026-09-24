import Combine
import Foundation
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var creditsObservers: Set<AnyCancellable> = []
    private var didReportAdAttribution = false

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        if connectionOptions.urlContexts.contains(where: { Self.isWalkthroughLink($0.url) }) {
            AppSettings.firstRunStage = .chooseDestination
        }
        NetworkMonitor.shared.start()
        observeCreditsEvents()

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = UIUserInterfaceStyle(rawValue: AppSettings.appearance.rawValue) ?? .unspecified
        window.rootViewController = Self.makeRoot()
        self.window = window
        window.makeKeyAndVisible()

        reportAdAttributionOnce()
        AppLogger.shared.info("scene connected", category: .app)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        reportAdAttributionOnce()
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard URLContexts.contains(where: { Self.isWalkthroughLink($0.url) }),
              let conversation = window?.rootViewController as? ConversationViewController
        else { return }
        AppLogger.shared.info("walkthrough link opened", category: .app)
        conversation.replayWalkthrough()
    }

    /// `psybeam://try`, the in-app event's deep link, replays the destination
    /// picker and try-it-yourself coach. A cold launch through it only has to
    /// reset the stored stage: the conversation screen then runs the walkthrough
    /// on its own once consent is settled.
    private static func isWalkthroughLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "psybeam" && url.host?.lowercased() == "try"
    }

    /// Reports the install attribution once per launch, driven from scene
    /// connection rather than scene activation.
    ///
    /// It must not wait for `sceneDidBecomeActive`: on the only launch that can
    /// ever produce an attribution, the first one after an ad-driven install, a
    /// permission alert is typically on screen, and a presented system alert keeps
    /// the scene `inactive` until the user answers it. The AdServices token is
    /// short-lived, so deferring capture until then loses the install. Nothing
    /// here touches the launch critical path: the reporter returns immediately and
    /// does its work on a detached task. Demo launches never report.
    private func reportAdAttributionOnce() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PSYBEAM_DEMO"] != nil { return }
        #endif
        guard !didReportAdAttribution else { return }
        didReportAdAttribution = true
        AICreditsManager.shared.reportAdAttribution()
    }

    /// The AICredits package emits no logging of its own, so the store's
    /// published identity/error/balance transitions are the only app-visible
    /// trace of bootstrap, Apple-link, refresh, and purchase outcomes.
    private func observeCreditsEvents() {
        let store = AICreditsManager.store
        store.$identity
            .compactMap { $0 }
            .removeDuplicates()
            .sink { AppLogger.shared.info("credits identity \($0.kind.rawValue) \($0.userID.prefix(8))", category: .auth) }
            .store(in: &creditsObservers)
        store.$error
            .compactMap { $0 }
            .sink { AppLogger.shared.error("credits error: \($0.localizedDescription)", category: .auth) }
            .store(in: &creditsObservers)
        store.$balance
            .removeDuplicates()
            .dropFirst()
            .sink { AppLogger.shared.info("credits balance \($0)", category: .auth) }
            .store(in: &creditsObservers)
    }

    private static func makeRoot() -> UIViewController {
        let provider = CreditsTranslationProvider(
            client: AICreditsManager.shared.client, baseURL: AICreditsManager.shared.baseURL)
        let travelerCall = RealtimeCallService(translationProvider: provider)
        let localCall = RealtimeCallService(translationProvider: provider)
        let viewModel = ConversationViewModel(travelerCall: travelerCall, localCall: localCall)
        Task {
            await AICreditsManager.store.bootstrap()
            await provider.settlePendingIfNeeded()
        }
        return ConversationViewController(viewModel: viewModel)
    }
}
