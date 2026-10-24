# Psybeam

Native UIKit iOS real-time voice-to-voice travel interpreter (bundle `com.guitaripod.psybeam`, team `P4DQK6SRKR`). The user holds the phone as sole operator with two thumb-buttons (their language, the other person's); the other person never touches it.
The backend is the shared mako AICredits service behind the Midgar gateway. `DESIGN.md` is the authoritative architecture, state machine and data model.

## Layout

- `Core/PsybeamCore/Sources/PsybeamCore`: platform-agnostic Swift 6 (state enums, Sendable protocols exposing `AsyncStream`, DTOs, `CldrLanguageTable`, GRDB records); builds and tests on Linux and macOS
- `App/`, `Features/`, `Resources/` and `Tests/` (xcodegen, UIKit, MVVM): `RealtimeCallService` (actor, `RTCPeerConnection` + `RTCAudioSession`), `LocationLanguageService`, `OpenAIRealtimeTranslate`; iOS 18+, iPhone-only, Swift 6, Mac build only
- `App/` (`PsybeamMidgar`, `LogCategories.swift`, `Services/` with `MakoGateway`), `Features/Settings/`, `scripts/`, `marketing/appstore/metadata/` (listing source of truth, push with `asc metadata push`), `store/privacy-label.md`
- Backend source lives in the monorepo's `services/intelligence`, not here

## Build and test (Mac only, always use the scripts)

```bash
scripts/setup.sh         # one-time: .env.local + xcodegen + spm
scripts/ios-build.sh     # device build, with staleness assertion
scripts/ios-deploy.sh    # build + install + relaunch on PSYBEAM_DEVICE_UDID
scripts/ios-test.sh      # PsybeamCore (SPM) + hosted iOS TranslationLeg tests on a simulator
```

- Never call `xcodebuild` raw. `ios-build.sh` runs `xcodegen generate` first and asserts no `.swift` is newer than the binary; adding or removing a file just means running it.
- Launch in the simulator after any isolation change, a trap only shows at runtime. Sign the simulator build ad hoc (`CODE_SIGN_IDENTITY=-`, not `CODE_SIGNING_ALLOWED=NO`) for the keychain group and Midgar ID, or it logs `keychain(status: -34018)`.
- Logs: `MidgarLog` writes os_log and `Library/Logs/psybeam.log` (categories in `App/LogCategories.swift`). Never `print`. Pull with the `ios-device-logs` skill or `devicectl ... copy from --source Library/Logs/psybeam.log`.
- Screenshots: `scripts/capture-screenshots.sh` + `scripts/frame-screenshots.swift`.

## Rules that break things

- Secrets: `.env.local` (gitignored, from `setup.sh`: `PSYBEAM_BUNDLE_ID`, `PSYBEAM_TEAM_ID`, `PSYBEAM_DEVICE_UDID`, `PSYBEAM_DEVICE_NAME`) is never committed. The app ships no API keys; backend secrets live on the mako worker via `wrangler secret put`. xcodegen reads the bundle and team ids from the environment.
- MidgarKit comes from the monorepo's `packages/MidgarKit` by path (`project.yml`, D15); the app links the `MidgarKit` umbrella product. AICredits comes from `packages/` by path too.
- Commerce engine is `storekit2`: `PsybeamMidgar.store` (a `MidgarStore`, mode purchases, no entitlements) sells the three minute packs and `PsybeamMidgar.credits` (a `MidgarCredits`) holds the balance on the Midgar ID wallet; both are nil in a test host or a demo capture (`reachesMidgarServices`). `App/Credits/PsybeamPacks.swift` is the one pack table the configurations and the tests read: `small` 45 credits $4.99, `medium` 120 credits $9.99, `large` 300 credits $19.99, products `com.guitaripod.psybeam.credits.<id>` (mako requires its `rc_product_prefix` plus the pack id; 1 credit is 1 minute). Never change product ids, prices or credit amounts without the founder. A purchase carries the Midgar ID as `appAccountToken`; MidgarCredits posts the signed transaction to mako's validate route, which credits the wallet under the key the webhook shares, so a credit lands once. MidgarCredits runs in legacy-key mode (`legacyAPIKey` is `AICreditsManager.legacyAPIKey()`), so the balance from before the move stays linked. RevenueCat is gone from the app; AICredits only registers the old per-app account and keeps its api key, which `CreditsTranslationProvider` sends on the realtime mint and settle.
- Credits UI: `CreditsModel` (`App/Credits/`) wraps MidgarCredits for the UIKit screens: the balance is read at launch, when the scene becomes active and after every settled realtime session, and follows `events()`; screens bind to its `balanceChanges`. The store is MidgarKit's `MidgarCreditStoreView` in `CreditStoreSheet` (`Features/Credits/`), opened from the Settings row and by the out-of-minutes notice and a 402 from the session start (that 402 carries no shortfall, so none is shown). The low-balance threshold is `CreditsModel.lowBalanceThreshold` (5). Demo captures use `DemoCreditsSource`. Apple Ads attribution is `MidgarCredits.reportAdAttributionOnce()` from `SceneDelegate`, only in a production launch (`PsybeamMidgar.isProductionLaunch`).
- Account deletion: `AccountService` deletes the old per-app account through `MidgarCredits.deleteLegacyAccount()` (AICredits' own delete when there is no wallet), then clears the local AICredits identity; a failure leaves everything local in place.
- StoreKit testing: `Products.storekit` at the app root holds the three consumables and is the Run action's StoreKit configuration (`project.yml`). `GatewayBacked` suites (`CreditsPurchaseStoreKitTests`, `CreditsWalletTests`) run serially against a `URLProtocol` stub of the gateway (`GatewayStub`). A purchase in the test host needs a window scene, which the test's purchasing wrapper supplies; the first purchase on a fresh simulator can stall, so rerun once.
- Keychain group `cc.midgarcorp.shared` sits after the app's own group, which stays first (AICredits keeps its api key there). No App Attest entitlement is needed.
- Gateway: AICredits uses `PsybeamMidgar.intelligenceURL` as base URL and `PsybeamMidgar.midgarTokenHeaders()` as `additionalHeaders`. Mint and settle go through `MakoGateway` and add `X-Midgar-Token` when the identity answers within two seconds; never wait on it, never send it twice. The WebRTC SDP exchange and audio stay direct to OpenAI.
- Transport: `gpt-realtime-translate` over WebRTC with a mako-minted ephemeral token, namespace `/v1/realtime/translations` (the general `/v1/realtime` path 404s). WebRTC owns the `AVAudioSession`: no hand-built `AVAudioEngine`; route the speaker with `.defaultToSpeaker`, never `overrideOutputAudioPort`.
- There is no closing `.done`/`.completed` event: a turn ends by caption quiescence (`TranslationLeg.scheduleSettle()`); never assume `isFinal` arrives. Input transcripts need `audio.input.transcription.model` set by the mint.
- Privacy: `Resources/PrivacyInfo.xcprivacy`, `store/privacy-label.md` and `web/midgarcorp/src/content/legal/psybeam/privacy.html` move together (policy URL `https://midgarcorp.cc/legal/psybeam/privacy`).
- App Review: 4.3 (translation spam), 5.1.2(i) (pre-audio third-party-AI consent, revocable), 3.1.2. Keep the visible cloud AI indicator; never claim "on-device" for the live path.
- Product stance: handset single-operator mode, not table mode, so do not rebuild it. Side colors: blue is the traveler, green the local. Your speech rotates 180 degrees to face them, their reply stays upright, the source line is never rotated.

## Conventions

- `final class`; `nonisolated struct: Sendable` for values; `@available(*, unavailable) required init?(coder: NSCoder) { fatalError() }` on every custom view/VC.
- Programmatic UIKit only, no storyboards; `UIStackView` first, then anchors. Swift 6 complete checking; the app target has MainActor default isolation, so pure data and URL types are `nonisolated`.
- No Combine in `PsybeamCore`. The `@MainActor` VM consumes streams in a `Task` and republishes through its own `PassthroughSubject<T, Never>` (never `@Published`); VCs bind in `viewDidLoad` with `Set<AnyCancellable>` and `.receive(on: DispatchQueue.main)`.
- GRDB: `nonisolated struct` records, `registerMigration("vN")`, migrations never edited after release; on-device only, transcripts never leave the phone.
- Liquid Glass on iOS 26 with `.systemThinMaterial` fallback on iOS 18. Settings is `MidgarSettingsViewController`. `ConversationViewController` is split into extensions, so its members are internal.
- No comments, no MARK, no file headers; extract a named method with a `///` doc comment. SPM only. Swift Testing, never XCTest.

## More in docs/agent-notes.md

Status and release history, growth funnel, backend and transport detail (Spikes 1 and 6), Midgar platform wiring, review prompt policy, product thesis, review gates. See also `docs/review-1.0.1-backlog.md`.
