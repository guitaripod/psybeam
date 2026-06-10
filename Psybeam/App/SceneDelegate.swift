import Combine
import Foundation
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var creditsObservers: Set<AnyCancellable> = []

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        NetworkMonitor.shared.start()
        observeCreditsEvents()

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = UIUserInterfaceStyle(rawValue: AppSettings.appearance.rawValue) ?? .unspecified
        window.rootViewController = Self.makeRoot()
        self.window = window
        window.makeKeyAndVisible()

        AppLogger.shared.info("scene connected", category: .app)
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
