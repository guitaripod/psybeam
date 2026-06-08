import Foundation
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        NetworkMonitor.shared.start()

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = UIUserInterfaceStyle(rawValue: AppSettings.appearance.rawValue) ?? .unspecified
        window.rootViewController = Self.makeRoot()
        self.window = window
        window.makeKeyAndVisible()

        AppLogger.shared.info("scene connected", category: .app)
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
