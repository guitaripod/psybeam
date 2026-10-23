import Foundation
import MidgarCore
import MidgarPortal

/// The composition root of everything Psybeam shares with the other Midgar apps: the Midgar ID, the gateway client
/// built on it, the anonymous signals client and the gateway address of mako. One instance lives for the whole
/// process, so there is one identity.
nonisolated final class PsybeamMidgar: Sendable {
    /// The registry slug: the `X-App-ID` of every gateway call and the id mako resolves to the `psybeam` tenant.
    static let appID = "psybeam"

    /// The bundle id the registry holds for the App Store record.
    static let bundleID = "com.guitaripod.psybeam"

    /// The log file name, kept from the retired per-app logger so the `ios-device-logs` workflow still finds it.
    static let logFileName = "psybeam.log"

    /// mako behind the gateway: `/v1/intelligence/` is stripped and the rest reaches mako's own routes, so
    /// `<this>/v1/credits/balance` is mako's `/v1/credits/balance`.
    static let intelligenceURL = MidgarHTTPConfiguration.defaultBaseURL.appendingPathComponent("v1/intelligence")

    static let shared = PsybeamMidgar()

    /// The Midgar ID client. Minted on first launch, attached on every later one, shared through the keychain group.
    let identity: MidgarIdentity

    /// The gateway client that carries the Midgar ID's bearer token, for the portal's "Your Midgar".
    let account: MidgarHTTPClient

    /// The app's own mako calls (realtime session mint and settle, account deletion), which keep the api key in
    /// `Authorization`.
    let mako: MakoGateway

    private init() {
        let configuration = MidgarHTTPConfiguration(appID: Self.appID)
        let identity = MidgarIdentity(httpConfiguration: configuration, bundleID: Self.bundleID)
        self.identity = identity
        account = MidgarHTTPClient(configuration: identity.authorizing(configuration))
        mako = MakoGateway(
            client: MidgarHTTPClient(configuration: configuration),
            midgarToken: Self.tokenSource(of: identity))
    }

    /// Where the app's mako calls get the Midgar token: the identity, or nothing in a host that reaches no Midgar
    /// service.
    private static func tokenSource(of identity: MidgarIdentity) -> @Sendable () async -> String? {
        guard reachesMidgarServices else { return { nil } }
        return { await accessToken(of: identity) }
    }

    /// The portal configuration of Settings: the authorized client, so "Your Midgar" shows what the person owns in
    /// the other apps and a cross-sell skips an app they already use.
    var portalConfig: MidgarPortal.MidgarConfig {
        MidgarPortal.MidgarConfig(placement: "settings", account: Self.reachesMidgarServices ? account : nil)
    }

    /// Opens the log file. Call first thing at launch so nothing before the rest of the setup is lost.
    static func configureLogging() {
        MidgarLog.configure(fileName: logFileName)
    }

    /// Configures anonymous signals for the portal and starts the Midgar ID in the background, so the app holds one
    /// before mako is first asked to link it. Call once at launch. A test host or a demo capture talks to no Midgar
    /// service.
    func start() {
        guard Self.reachesMidgarServices else {
            MidgarLog.info("Midgar services not started: test host or demo", category: .account)
            return
        }
        MidgarSignals.configure(configuration: MidgarHTTPConfiguration(appID: Self.appID))
        let identity = identity
        Task {
            do {
                _ = try await identity.midgarId
                MidgarLog.info("Midgar ID ready", category: .account)
            } catch {
                MidgarLog.info("Midgar ID not available yet: \(error)", category: .account)
            }
        }
    }

    /// Removes the log files, for the account deletion that starts the app over.
    static func eraseLogFiles() {
        MidgarLog.flush()
        for url in MidgarLog.logFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// False inside an XCTest or Swift Testing host and in a DEBUG demo capture, which must not mint identities or
    /// send signals to the production services.
    static var reachesMidgarServices: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
        #if DEBUG
        if ProcessInfo.processInfo.environment["PSYBEAM_DEMO"] != nil { return false }
        #endif
        return true
    }

    /// The Midgar ID's access token, or nil when it cannot be had within `MakoGateway.tokenWaitSeconds`. A call that
    /// waits on a slow identity service would be slower than the call it decorates.
    private static func accessToken(of identity: MidgarIdentity) async -> String? {
        try? await AsyncTimeout.run(seconds: MakoGateway.tokenWaitSeconds) { try await identity.accessToken() }
    }
}
