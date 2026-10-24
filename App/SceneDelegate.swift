import Combine
import Foundation
import UIKit
import MidgarCore

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let credits = CreditsModel.live()
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
        Task { await credits.start() }

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = UIUserInterfaceStyle(rawValue: AppSettings.appearance.rawValue) ?? .unspecified
        window.rootViewController = makeRoot()
        self.window = window
        window.makeKeyAndVisible()

        reportAdAttributionOnce()
        MidgarLog.info("scene connected", category: .app)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        reportAdAttributionOnce()
        Task { await credits.refresh() }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard URLContexts.contains(where: { Self.isWalkthroughLink($0.url) }),
              let conversation = window?.rootViewController as? ConversationViewController
        else { return }
        MidgarLog.info("walkthrough link opened", category: .app)
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
    /// here touches the launch critical path: the wallet does the work on its own
    /// actor and remembers mako's verdict, so an install is settled once. A test
    /// host, a demo capture and a debug build have no wallet or say it is not a
    /// production launch, and report nothing.
    private func reportAdAttributionOnce() {
        guard !didReportAdAttribution, let wallet = PsybeamMidgar.shared.credits else { return }
        didReportAdAttribution = true
        Task {
            let result = await wallet.reportAdAttributionOnce()
            MidgarLog.info("ad attribution \(result.logDescription)", category: .auth)
        }
    }

    /// The balance transitions are the only app-visible trace of the wallet, so each change is written to the file log.
    private func observeCreditsEvents() {
        credits.balanceChanges
            .sink { MidgarLog.info("credits balance \($0)", category: .auth) }
            .store(in: &creditsObservers)
    }

    private func makeRoot() -> UIViewController {
        let credits = credits
        let provider = CreditsTranslationProvider(client: AICreditsManager.shared.client, onSettled: { await credits.refresh() })
        let travelerCall = RealtimeCallService(translationProvider: provider)
        let localCall = RealtimeCallService(translationProvider: provider)
        let viewModel = ConversationViewModel(travelerCall: travelerCall, localCall: localCall)
        Task { await provider.settlePendingIfNeeded() }
        return ConversationViewController(viewModel: viewModel, credits: credits)
    }
}
