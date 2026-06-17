import Foundation

/// Public product URLs. The privacy page (hosted on the mako backend) is the
/// authoritative disclosure for App Review 5.1.1(i): it names OpenAI as the
/// translation processor, the data sent, and how it's used.
enum Links {
    static let privacyPolicy = URL(string: "https://mako.midgarcorp.cc/privacy/psybeam")!
    static let terms = URL(string: "https://mako.midgarcorp.cc/terms/psybeam")!
}
