import UIKit

enum OrientationCoordinator {
    nonisolated(unsafe) static var mask: UIInterfaceOrientationMask = .portrait
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationCoordinator.mask
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        warmUpLaunchServicesReceiptPath()
        _ = DatabaseManager.shared
        AppLogger.shared.info("app launched", category: .app)
        return true
    }

    /// Pre-warms the LaunchServices XPC connection behind
    /// `Bundle.main.appStoreReceiptURL` on the main thread. RevenueCat reads
    /// the receipt URL from its background "RC Backend Queue" while
    /// configuring, which crashes deterministically at launch on iOS 26.5
    /// devices (EXC_BREAKPOINT during _LSDReadService setup —
    /// RevenueCat/purchases-ios#6886, unfixed as of 5.78.0). A warm
    /// main-thread access first makes the later background read safe.
    private func warmUpLaunchServicesReceiptPath() {
        _ = Bundle.main.appStoreReceiptURL
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
