import Foundation
import MidgarCommerce
import MidgarCore
import MidgarCredits
import MidgarPortal

/// The composition root of everything Psybeam shares with the other Midgar apps: the Midgar ID, the gateway client
/// built on it, the credit store and wallet, the anonymous signals client and the gateway address of mako. One instance lives for the whole
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

    /// The purchase engine for the credit packs: StoreKit 2 with the Midgar ID as `appAccountToken`. Nil in a test host
    /// or a demo capture, which must not reach the ledger.
    let store: MidgarStore?

    /// The wallet behind the credit packs: the balance, the purchase and the credit on the Midgar ID, with the old
    /// AICredits api key as the legacy key so the balance from before the move stays linked. Nil where `store` is.
    let credits: MidgarCredits?

    private init() {
        let configuration = MidgarHTTPConfiguration(appID: Self.appID)
        let identity = MidgarIdentity(httpConfiguration: configuration, bundleID: Self.bundleID)
        self.identity = identity
        let account = MidgarHTTPClient(configuration: identity.authorizing(configuration))
        self.account = account
        mako = MakoGateway(
            client: MidgarHTTPClient(configuration: configuration),
            midgarHeaders: { await Self.tokenHeaders(of: identity) })
        let commerce = Self.makeCommerce(identity: identity, account: account, configuration: configuration)
        store = commerce?.store
        credits = commerce?.credits
    }

    /// Builds the store and the wallet on it, or nothing where the app reaches no Midgar service. The wallet takes the
    /// plain configuration, because it authorizes its own requests: the legacy key and the Midgar token travel in
    /// different headers.
    private static func makeCommerce(
        identity: MidgarIdentity,
        account: MidgarHTTPClient,
        configuration: MidgarHTTPConfiguration
    ) -> (store: MidgarStore, credits: MidgarCredits)? {
        guard reachesMidgarServices else { return nil }
        let store = MidgarStore(configuration: PsybeamPacks.storeConfiguration(), identity: identity, http: account)
        let credits = MidgarCredits(
            configuration: PsybeamPacks.creditsConfiguration(),
            http: configuration,
            identity: identity,
            purchasing: store,
            legacyAPIKey: { await AICreditsManager.shared.legacyAPIKey() }
        )
        return (store, credits)
    }

    /// The longest a call waits for the Midgar ID's access token before it goes without.
    static let tokenWait: Duration = .seconds(2)

    /// The `X-Midgar-Token` header for a call to mako, which is how mako links the legacy api key to the Midgar ID,
    /// or nothing when the identity cannot answer within `tokenWait` or the host reaches no Midgar service. A call
    /// never waits on or fails for the token.
    func midgarTokenHeaders() async -> [String: String] {
        await Self.tokenHeaders(of: identity)
    }

    private static func tokenHeaders(of identity: MidgarIdentity) async -> [String: String] {
        guard reachesMidgarServices else { return [:] }
        return await identity.midgarTokenHeader(within: tokenWait).map { [$0.name: $0.value] } ?? [:]
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

    /// True only for the shipped app on a real launch: the Apple Ads install attribution is reported then and never from a
    /// debug build, a test host or a demo capture.
    static var isProductionLaunch: Bool {
        #if DEBUG
        false
        #else
        reachesMidgarServices
        #endif
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
}
