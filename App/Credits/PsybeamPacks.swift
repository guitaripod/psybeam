import Foundation
import MidgarCommerce
import MidgarCredits

/// The credit packs Psybeam sells, in one place: the store configuration, the credits configuration and the tests all
/// read this table. The ids and amounts are mako's catalog for the `psybeam` tenant, and mako requires each product id
/// to be its `rc_product_prefix` (`com.guitaripod.psybeam.credits.`) plus the pack id. Prices are StoreKit's, from the
/// App Store records and `Products.storekit`. Changing an id, an amount or a price is the founder's decision.
nonisolated enum PsybeamPacks {
    static let small = MidgarCreditsPack(id: "small", productID: "com.guitaripod.psybeam.credits.small", credits: 45)
    static let medium = MidgarCreditsPack(id: "medium", productID: "com.guitaripod.psybeam.credits.medium", credits: 120)
    static let large = MidgarCreditsPack(id: "large", productID: "com.guitaripod.psybeam.credits.large", credits: 300)

    static let all = [small, medium, large]

    static let productIDs = all.map(\.productID)

    /// The store sells the three consumables and grants no entitlement: Psybeam has no Pro tier and no subscription.
    static func storeConfiguration(directory: URL? = nil) -> MidgarStoreConfiguration {
        MidgarStoreConfiguration(
            appID: PsybeamMidgar.appID,
            productIDs: productIDs,
            entitlementsByProduct: [:],
            mode: .purchases,
            directory: directory
        )
    }

    /// The wallet's packs. `isProductionLaunch` decides whether the Apple Ads attribution is reported: only the shipped
    /// app does, never a debug build, a test host or a demo capture.
    static func creditsConfiguration(
        directory: URL? = nil,
        attributionTokenProvider: any MidgarAdAttributionTokenProviding = MidgarAdServicesTokenProvider(),
        isProductionLaunch: @escaping @Sendable () -> Bool = { PsybeamMidgar.isProductionLaunch }
    ) -> MidgarCreditsConfiguration {
        MidgarCreditsConfiguration(
            packs: all,
            directory: directory,
            attributionTokenProvider: attributionTokenProvider,
            isProductionLaunch: isProductionLaunch
        )
    }
}
