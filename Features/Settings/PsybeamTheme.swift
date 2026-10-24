import MidgarUI

extension MidgarTheme {
    /// Psybeam's look: the blue of its brand on the deep indigo of the conversation screen, and a pale indigo-white
    /// canvas by day.
    nonisolated static let psybeam = MidgarTheme(
        accent: MidgarColor(lightHex: 0x2B7DE9, darkHex: 0x4D9EFF),
        background: MidgarColor(lightHex: 0xF3F5FF, darkHex: 0x0B0C1B),
        surface: MidgarColor(lightHex: 0xFFFFFF, darkHex: 0x171A30)
    )
}
