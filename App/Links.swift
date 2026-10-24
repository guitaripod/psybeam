import Foundation

/// Public product URLs. The privacy page (published on midgarcorp.cc from
/// `web/midgarcorp`) is the authoritative disclosure for App Review 5.1.1(i): it
/// names OpenAI as the translation processor, the data sent, and how it's used.
enum Links {
    static let privacyPolicy = URL(string: "https://midgarcorp.cc/legal/psybeam/privacy")!
    static let appStore = URL(string: "https://apps.apple.com/app/id6777952645")!
    static let writeReview = URL(string: "https://apps.apple.com/app/id6777952645?action=write-review")!
}
