# Psybeam — Agent Instructions

Native UIKit iOS **real-time voice-to-voice travel interpreter** with a Cloudflare Worker backend that brokers ephemeral OpenAI Realtime tokens (the real key never leaves Cloudflare). **You hold the phone and you are the sole operator** — two thumb-buttons (your language / their language); you hold yours to speak and it speaks theirs aloud, you hold theirs while they reply and it speaks yours. The stranger you walked up to **never touches the phone**: the audio carries the translation, and when it's their turn the screen invites them to speak in their own language. The local language auto-suggests by GPS as you cross borders.

See `DESIGN.md` for the authoritative architecture, the backend decision, the state machine, the data model, and the spikes that gate the build. This file is the working guide.

## Status

Greenfield — foundation scaffolded & green. **Spike 1 is RESOLVED (2026-06-07):** the `gpt-realtime-translate` mint + endpoints (`/v1/realtime/translations`) and 20+-language output are verified live; the Worker targets these endpoints. **Run the remaining spikes in `DESIGN.md` §11 before writing the §4 audio code** — table-mode echo on real hardware (Spike 2) and turn-taking (Spike 3) are still unproven. Do not commit to the audio path or the turn-taking model before Spikes 2 and 3 pass.

## Stack

- **PsybeamKit** (`Sources/PsybeamKit`): platform-agnostic Swift 6 — `TranslationState`/`Side`/`CallState` enums, `RealtimeCallProviding`/`TranslationProviding`/`LocationLanguageProviding`/`Translating` **Sendable** protocols exposing `AsyncStream` (no UIKit/AVFoundation/Combine imports), provider DTOs, `CldrLanguageTable` + `LocaleSuggestion`, GRDB record structs. **Compiles and tests on Linux and macOS.**
- **Psybeam** (`Psybeam/`, xcodegen): programmatic UIKit, MVVM. Combine `PassthroughSubject` lives **only** at the VM↔VC seam. `RealtimeCallService` (actor, owns `RTCPeerConnection` + `RTCAudioSession`), `LocationLanguageService` (actor over CoreLocation), `OpenAIRealtimeTranslate` adapter (the Azure fallback adapter is retired — Spike 1 disproved the output-language ceiling). Swift 6 strict concurrency, iOS 18+ deploy target / iOS 26 SDK, iPhone-only. Darwin-only — build on a Mac.
- **workers/** (`psybeam-worker`): Cloudflare Workers (Hono v4, jose v6, KV + D1). Sign in with Apple → HS256 app JWT; ephemeral `ek_` mint; **atomic** per-user minute quota; usage ledger. TypeScript, vitest. No Durable Object.

## Backend

`gpt-realtime-translate` (OpenAI speech-to-speech, auto-detects source, mimics speaker voice) over **WebRTC direct from device**, using a Worker-minted ephemeral token — so the audio never touches our infrastructure and the real key stays on Cloudflare. Served under the dedicated `/v1/realtime/translations` namespace (mint at `/v1/realtime/translations/client_secrets`, SDP at `/v1/realtime/translations/calls`); the general `/v1/realtime` path 404s the translate inference. **WebRTC owns the `AVAudioSession`; there is no hand-built `AVAudioEngine` graph.** Route the speaker via the `.defaultToSpeaker` category option, never `overrideOutputAudioPort` (it reverts on ICE-connect). Spike 1 (2026-06-07) verified the model translates 20+ languages, so the **Azure "Live Interpreter" breadth-fallback tier is retired** (there was no 13-output ceiling). `gpt-realtime-2` (instruction-steered) is the emergency fallback; Apple on-device (`SpeechAnalyzer` + Translation framework) is the no-signal fallback — never primary.

## Code style (non-negotiable)

- `final class` for classes; `nonisolated struct: Sendable` for value types.
- `@available(*, unavailable) required init?(coder: NSCoder) { fatalError() }` on every custom view/VC.
- Programmatic only — no storyboards/XIB. `UIStackView` first, then anchors.
- Core surfaces expose `AsyncStream`/`AsyncSequence` and **Sendable** protocols — no Combine in `PsybeamKit`. The `@MainActor` VM consumes the stream in a `Task` and republishes to the VC via its own `PassthroughSubject<T, Never>` (never `@Published`); VCs bind in `viewDidLoad`, hold `Set<AnyCancellable>`, `.receive(on: DispatchQueue.main)`.
- Service protocols in `PsybeamKit` where platform-agnostic; concrete singletons (`.shared`) injected through inits with defaults.
- GRDB: `nonisolated struct` records, `DatabaseMigrator.registerMigration("vN")`, never edited after release. On-device only — transcripts never leave the phone.
- `UIBackgroundConfiguration.listCell()` on list cells. SF Symbol effects (`.pulse` repeat on listening, `.variableColor` on waveforms, `.bounce`/`.replace` on completion). Liquid Glass (`UIGlassEffect`/`UIGlassContainerEffect`) on iOS 26, `.systemThinMaterial` fallback on iOS 18.
- No comments, no MARK, no file headers. `///` doc comments sparingly. SPM only.
- Swift Testing (`@Test`, `#expect`) — never XCTest.

## Build & deploy — MANDATORY: use the scripts (Mac only)

xcodegen regenerates `Psybeam.xcodeproj` from `project.yml` on every build, so:

```bash
scripts/setup.sh         # one-time: .env.local + Secrets.swift + xcodegen + spm
scripts/ios-build.sh     # device build, with staleness assertion
scripts/ios-deploy.sh    # build + install + relaunch on PSYBEAM_DEVICE_UDID
```

`ios-build.sh` runs `xcodegen generate` first, captures the real xcodebuild exit code via `pipefail`, surfaces Swift 6 concurrency errors, and asserts no `.swift` is newer than the built binary. Adding/removing any file → just run `ios-build.sh`. Never call `xcodebuild` raw.

```bash
cd workers
npm install
npm run typecheck
npm test
CLOUDFLARE_API_TOKEN=$(cat ~/.cloudflare-api-token) npx wrangler dev     # local
CLOUDFLARE_API_TOKEN=$(cat ~/.cloudflare-api-token) npx wrangler deploy   # prod
```

## Logging — agents read this

`AppLogger` mirrors os_log AND `Library/Logs/psybeam.log` (rotates at 2 MB). Categories: `app, auth, session, webrtc, audio, location, translate, persistence, ui`. To pull from a device, use the `ios-device-logs` skill / `devicectl ... copy from --source Library/Logs/psybeam.log`.

## Secrets / config

`.env.local` (gitignored, made by `setup.sh`): `PSYBEAM_BUNDLE_ID`, `PSYBEAM_TEAM_ID`, `PSYBEAM_DEVICE_UDID`, `PSYBEAM_DEVICE_NAME`. `Psybeam/Secrets.swift` (gitignored, from `Secrets.example.swift`): `workerBaseURL`, `redirectURI`. Worker secrets via `wrangler secret put` (prod) + `workers/.dev.vars` (local): `OPENAI_API_KEY`, `APP_JWT_SECRET`, `APPLE_CLIENT_ID`, `APPLE_TEAM_ID`. Never commit any of them.

## Reality

- The product thesis is the **handset, single operator**: you hold the phone and drive both directions from two thumb-buttons; the stranger you approached never operates it and isn't expected to possess this tech. The side-color contract holds (blue = traveler/you, green = local/them) on the buttons + wave, but the bystander's comprehension comes from **audio + an in-their-language "speak now" prompt**, not from reading the UI. This is **handset mode, not flat-on-a-table dual-facing** — do not rebuild table mode. Text orientation is **automatic by audience** (no manual flip control): your speech (rendered in their language) rotates 180° to face them; their reply (in your language) stays upright for you. The source/confirmation line is never rotated, so you always have an upright read of what was heard.
- The feared **~13-language speech ceiling was disproved** (Spike 1, 2026-06-07): `gpt-realtime-translate` speaks 20+ languages — including the Arabic/Thai/Turkish/Greek/Polish corridors — with `en→en` passthrough. So the Azure breadth-fallback tier is **retired**. `OPENAI_TRANSLATE_OUTPUT_LANGS` survives as informational server-config for `/v1/config` display only — it is **not** a gate and is never hardcoded in the binary.
- App Review is a three-front gate: **4.3** (translation-app spam — lead screenshots with the table moment), **5.1.2(i)** (pre-audio third-party-AI consent, revocable), **3.1.2** (ongoing value). The bystander cannot consent to cloud routing → a visible "cloud AI" indicator on the local's half is the honest floor. Never claim "on-device" for the live path.
