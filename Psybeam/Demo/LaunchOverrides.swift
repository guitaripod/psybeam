#if DEBUG
import Foundation
import PsybeamKit

/// DEBUG-only launch environment that forces the pre-session notice states a
/// simulator cannot reach on its own: `PSYBEAM_FORCE_OFFLINE=1` reports no
/// connection, `PSYBEAM_FORCE_BALANCE=<n>` reports that many minutes and
/// `PSYBEAM_DEBUG_PRESS=traveler|local` presses that talk button once the
/// screen has appeared, for reaching the first-hold microphone prompt.
struct LaunchOverrides {
    static let current = LaunchOverrides(environment: ProcessInfo.processInfo.environment)

    let offline: Bool
    let balance: Int?
    let press: Side?

    init(environment: [String: String]) {
        offline = environment["PSYBEAM_FORCE_OFFLINE"] == "1"
        balance = environment["PSYBEAM_FORCE_BALANCE"].flatMap(Int.init)
        press = environment["PSYBEAM_DEBUG_PRESS"].flatMap(Side.init(rawValue:))
    }
}
#endif
