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

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = UIUserInterfaceStyle(rawValue: AppSettings.appearance.rawValue) ?? .unspecified
        window.rootViewController = Self.makeRoot()
        self.window = window
        window.makeKeyAndVisible()

        AppLogger.shared.info("scene connected", category: .app)
    }

    private static func makeRoot() -> UIViewController {
        let baseURL = URL(string: Secrets.workerBaseURL) ?? URL(string: "https://example.com")!
        let keychain = KeychainStore.shared
        let auth = AuthService(baseURL: baseURL, keychain: keychain)
        let worker = WorkerClient(baseURL: baseURL, keychain: keychain)
        let travelerCall = RealtimeCallService(translationProvider: worker)
        let localCall = RealtimeCallService(translationProvider: worker)
        let viewModel = ConversationViewModel(travelerCall: travelerCall, localCall: localCall)
        return ConversationViewController(viewModel: viewModel, auth: auth, worker: worker)
    }
}
