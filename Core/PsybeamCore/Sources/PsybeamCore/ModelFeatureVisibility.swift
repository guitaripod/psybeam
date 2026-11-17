/// The model-feature surfaces Psybeam shows, decided by whether Midgar's servers answer model calls where the device
/// connects from.
///
/// Live translation is the app's model feature and the core of what it sells. Where Midgar refuses model calls, nothing
/// that starts a session is shown: no talk buttons, no cloud mark, no minutes notice, no onboarding that teaches the
/// buttons, no minutes or store. The conversation says the region line instead (`MidgarModelRegion.unavailableMessage`).
public struct ModelFeatureVisibility: Sendable, Equatable {
    public let modelsAvailable: Bool

    public init(modelsAvailable: Bool) {
        self.modelsAvailable = modelsAvailable
    }

    /// The hold-to-talk buttons and the cloud AI mark that describes what they send.
    public var showsTalkButtons: Bool { modelsAvailable }

    /// The upfront notice about connection and minutes.
    public var showsSessionNotice: Bool { modelsAvailable }

    /// Consent, the destination picker, the first-run coach and the location offer that serve the talk buttons.
    public var offersOnboarding: Bool { modelsAvailable }

    /// The minutes section of Settings and the credit store sheet.
    public var offersPurchases: Bool { modelsAvailable }

    /// Whether the conversation may connect its legs ahead of a hold, which mints a realtime session.
    public var startsSessions: Bool { modelsAvailable }

    /// Whether the screen says `MidgarModelRegion.unavailableMessage` where the feature would be.
    public var showsRegionLine: Bool { !modelsAvailable }
}
