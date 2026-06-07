> Authoritative design for **Psybeam** — a real-time voice-to-voice travel interpreter.
> Produced from a verified multi-agent research workflow (June 2026). Claims flagged *unverified* are gated by the spikes in §11.

# Psybeam — Architecture & Design

This is the build document. Every P0/P1/P2 from the principal review is resolved or explicitly deferred with a reason. Load-bearing assumptions that remain unverified are isolated into **§11 Spikes** and must be proven before the code they gate is written.

---

## 0. Decisions Log — locked 2026-06-06

| # | Decision | Locked choice |
|---|---|---|
| Name | App name | **Psybeam** (`com.guitaripod.psybeam`) — clean App Store namespace, sibling to Solar Beam / Psywave. Findability via keyword subtitle, not the brand. |
| A | Backend posture | **OpenAI `gpt-realtime-translate` — VERIFIED WORKING (Spike 1) via `/v1/realtime/translations`, 20+ languages, flat $0.034/min, no drift.** Azure fallback tier **retired** (the 13-language ceiling was disproved). `gpt-realtime-2` (instruction-steered) is the proven emergency fallback. Apple on-device for no-signal. |
| B | Monetization | **Free 10 min/day → sub $9.99/mo · $59.99/yr → v1 trip-packs $19.99/300min · $34.99/600min.** BYO-key deferred (OpenAI ToS check). |
| C | Turn-taking default | **Auto-VAD + half-tap override** — *contingent on Spike 2*; falls back to hold-to-talk handset if the noisy-room echo test fails. |
| D | Offline scope | **v1, not MVP.** MVP uses online `CLGeocoder` reverse-geocoding. |

**Foundation scaffolded & green (2026-06-06):** PsybeamKit core (21 tests), psybeam-worker (38 tests, typecheck clean), iOS app (`xcodebuild BUILD SUCCEEDED`).

**Spike 1 — RESOLVED (2026-06-07).** `gpt-realtime-translate` is served ONLY under the dedicated `/v1/realtime/translations` namespace (the general `/v1/realtime` path 404s its inference — `inference_not_found_error`). Verified flow, live against the API:
- **Mint (Worker):** `POST https://api.openai.com/v1/realtime/translations/client_secrets`, body `{ session: { model, audio: { output: { language } } } }` (NO `type` field) → `{ value: "ek_…", expires_at, session.type:"translation" }`.
- **WebRTC (iOS):** SDP exchange at `POST /v1/realtime/translations/calls` (Bearer `ek_`).
- **WebSocket (server alt):** `wss://…/v1/realtime/translations?model=…`, `session.`-prefixed events, **automatic** (append audio → it emits `session.output_transcript.delta` / `session.output_audio.delta`; no `response.create`).
- **Coverage:** translated faithfully into **20+ languages** (es/pt/fr/de/it/nl/ru/pl/tr/el/ar/he/hi/ja/ko/zh/th/vi/id/fi/sv); `en→en` correctly emits the **passthrough** (empty) case. **No 13-language ceiling → Azure tier removed.** `gpt-realtime-2` also translates (instruction-steered) but drifts (occasionally answers) and is ~2–4× pricier + metered — emergency fallback only.

The Worker (`openai.ts`/`session.ts`/`config.ts`) now targets these endpoints; the output-language gate + Azure 422 path are removed. The live-audio path (§4) remains gated by **Spikes 2–3** (device echo + turn-taking).

---

## 1. EXECUTIVE SUMMARY

Phone-only, pull-out-of-pocket, real-time voice-to-voice interpreter built **for the clueless local**, not the owner: a flat-on-table, color-coded, dual-facing UI where a stranger understands the conversation from visuals alone, and the local language auto-suggests by GPS as the user crosses borders. Backend is **OpenAI `gpt-realtime-translate`** (purpose-built single-model speech-to-speech interpreter, auto-detects source, dynamic speaker-voice mimicry, $0.034/min — [model page](https://developers.openai.com/api/docs/models/gpt-realtime-translate), [announcement](https://openai.com/index/advancing-voice-intelligence-with-new-models-in-the-api/), May 2026), with **Azure AI Speech "Live Interpreter"** as the breadth/output-coverage fallback and **Apple on-device** for no-signal.

The Cloudflare pattern is **ephemeral-token-mint (Pattern A), not a media relay**: a Hono Worker mints short-lived `ek_` client secrets gated by Sign-in-with-Apple; the iPhone connects **directly to OpenAI over WebRTC** so audio never traverses our infrastructure.

**Five things changed from the prior design after engineering review, in priority order:**
1. **Transport contradiction resolved → WebRTC owns the audio, the hand-built `AVAudioEngine` graph is deleted.** Native WebRTC seizes the `AVAudioSession` singleton and resets `overrideOutputAudioPort(.speaker)` to earpiece on ICE-connect ([confirmed, multiple production reports](https://groups.google.com/g/discuss-webrtc/c/44ogyfkIC0w)). You cannot run a parallel engine. §4 is rewritten around `RTCAudioSession` manual-audio coordination. This is a *net simplification* — converters, jitter-buffer continuations, and resampling all evaporate.
2. **Table-mode echo is now a gated spike, not a shipped default-on assumption** (Spike 2). It ships as default *only if* it survives a noisy-room test on real hardware.
3. **Abuse model corrected:** the real attack surface is a leaked **app JWT** minting unbounded sessions, not one leaked `ek_`. Fix = **atomic KV debit at mint time** + concurrent-session cap + per-user mint rate-limit. The 60-min OpenAI hard cap is **real and enforced** ([raised 30→60 min at GA, terminates with `session_expired`](https://developers.openai.com/blog/realtime-api)), so per-session exposure is bounded, but daily exposure without atomic reservation is not.
4. **Guideline 4.3 (Spam/duplicate)** — the most common translation-app rejection — is now a top risk and drives the App Review submission strategy.
5. **MVP trimmed hard.** The Living Seam fluid physics and the offline polygon engine — the two least-validated, highest-schedule-risk features — move out of MVP. MVP ships a **simple color-fill divider** (the color *contract* is what the local learns, not a fluid sim) and **online `CLGeocoder`** reverse-geocoding (offline polygons become a v1 feature, which they already were for the no-signal path).

**The two headline product risks are unchanged and structural:** (a) the **13-output-language ceiling** (OpenAI *understands* 70+ but can only *speak* 13 — count confirmed everywhere, the *exact list* is unverified in secondary sources and is **Spike 1**), which blinds the MENA/Turkey/Thailand/Eastern-Europe corridors; and (b) **App Review** — now a three-front gate: **5.1.2(i)** (third-party-AI consent), **4.3** (spam), **3.1.2** (ongoing value).

---

## 2. THE BACKEND DECISION

> **VERIFIED 2026-06-07 (Spike 1) — supersedes the framing below.** `gpt-realtime-translate` works via the dedicated `/v1/realtime/translations` namespace and translates **20+ languages** at flat $0.034/min with no drift. **There is no 13-language ceiling, so the Azure fallback tier is retired.** See §0 for the verified mint/endpoint flow. The "13 output languages / Azure breadth" reasoning below is historical.

**Primary: OpenAI `gpt-realtime-translate`. Fallback (broad output): Azure AI Speech "Live Interpreter." Offline: Apple Translation + SpeechAnalyzer.** Unchanged from prior; the review concurred. Corrections folded in:

**Verified facts (2026-06-06):**
- **Languages:** 70+ input → **13 output** (count confirmed across [OpenAI](https://openai.com/index/advancing-voice-intelligence-with-new-models-in-the-api/), [Brockman](https://x.com/gdb/status/2060452095279415725), [9to5Mac](https://9to5mac.com/2026/05/07/openai-has-new-voice-models-that-reason-translate-and-transcribe-as-you-speak/)). **The exact enumeration of the 13 is NOT confirmed by any authoritative source I can cite** — the prior design's list (ES/PT/FR/JA/RU/ZH/DE/KO/HI/ID/VI/IT/EN) is a working assumption only. **→ Spike 1 fetches the live list at runtime; the Worker treats the list as server-config, never hardcoded in the binary.**
- **Pricing:** $0.034/min, billed by audio duration ([model page](https://developers.openai.com/api/docs/models/gpt-realtime-translate)). **COGS re-derived below** — the prior $0.048/wall-clock-min was wrong for the bidirectional design.
- **Session cap: 60 min, OpenAI-enforced, hard** (GA raised it from 30; terminates `session_expired` — [dev blog](https://developers.openai.com/blog/realtime-api)). **Azure-hosted OpenAI caps at 30 min** — irrelevant to us (we hit OpenAI direct) but it means **if we ever route translate through Azure OpenAI the cap halves**; Azure *Speech* Live Interpreter is a different service with its own session model.
- **Ephemeral tokens:** `POST /v1/realtime/...client_secrets` → `ek_`, `expires_after:{anchor,seconds}` (default ~60s) governs the **connect window only**; it does **not** terminate a live session ([confirmed](https://community.openai.com/t/how-to-limit-openai-realtime-api-sessions-to-x-minutes-max/1365611)). The 60-min cap is what bounds a connected session.

**COGS, re-derived (the review was right, the prior number was wrong).** A bidirectional conversation needs translation in **both directions**. If we held **two persistent full-duplex sessions** open, we'd pay ~2× wall-clock including inter-phrase silence. **We don't.** §3 mints/opens **only the active-turn direction** (VAD side-detection gates which session is live) and tears it down on turn-end/idle. Realistic COGS: turn-based, one direction live at a time, ≈ **1.0–1.3× wall-clock** of actual speech, not 2×. **10-day trip @ 30 min/day ≈ $12–22 COGS** — wider band than the prior $15–18, honestly reflecting that we have **not** measured real silence/turn overhead (Spike 3 measures it). **Trip-packs are priced against the 2× worst case** so we never sell at a loss.

**Azure over Gemini for breadth (unchanged):** Azure Live Interpreter gives open-range source LID + mid-stream language switching + Personal Voice + 140+ languages covering every OpenAI output gap, and lets you **pin the target language deterministically**. Gemini native-audio **auto-selects output and rejects explicit locale codes** — fatal for a translator. **Azure Live Interpreter + Personal Voice are Limited-Access — apply for approval on day 1; it is the long pole for the entire fallback tier.** (I could not re-verify current Azure approval timelines this session — treat as unverified, apply immediately regardless.)

**Offline stance (unchanged, but now a v1 feature, see §9):** iOS 26 `SpeechAnalyzer`/`DictationTranscriber` → iOS 18 `TranslationSession` → `AVSpeechSynthesizer`, GPS-prefetched packs. Never primary. **Seamless/SeamlessM4T excluded (CC-BY-NC, illegal to ship commercially).** Qwen3-Omni (Apache-2.0) deferred past v2 (needs a GPU box).

---

## 3. ARCHITECTURE — THE 3-PART STRUCTURE

Mirrors golf-coach / embr exactly.

| Part | Name | Contents |
|---|---|---|
| **(1) SPM core** | **`PsybeamKit`** (Swift 6, **Linux-compiles, NO UIKit/AVFoundation/Combine — Combine fully removed**, see §10) | `TranslationState`/`Side` enums; `TranslationProviding`/`LocationLanguageProviding`/`Translating` **Sendable** protocols exposing **`AsyncStream`/`AsyncSequence`** (no `AnyPublisher`); provider-agnostic request-spec structs; WS/WebRTC message DTOs; `CountryLocator` (online + offline impls) + `CldrLanguageTable` + `LocaleSuggestion` (pure value types); GRDB record structs. |
| **(2) iOS app** | **`Psybeam`** (programmatic UIKit, MVVM+Combine) | `ConversationViewController` (@MainActor), `RealtimeCallService` (actor, owns `RTCPeerConnection` + `RTCAudioSession`), `LocationLanguageService` (actor over CoreLocation), `OpenAIRealtimeTranslate`/`AzureLiveInterpreter` adapters, simple color-fill divider view, Liquid-Glass caption cards. **Combine lives only here, at the VM↔VC boundary.** |
| **(3) workers/** | **`psybeam-worker`** (Hono v4, jose v6, TypeScript, vitest) | Sign-in-with-Apple → HS256 app JWT; ephemeral-token mint; `/v1/config` language gate; **KV atomic quota**; D1 usage ledger. **No Durable Object.** |

**LIVE AUDIO PATH — WebRTC owns I/O (the §4 rewrite):**

```
                         ┌──────────── iPhone (Psybeam target) ────────────┐
  Local/Traveler speaks  │  RTCPeerConnection owns:                       │
        ║                │    • mic capture + VoiceProcessingIO (AEC/AGC) │
        ║   ① mint req   │    • Opus encode / FEC / jitter buffer         │
        ╚═══════════════▶│    • render to output (DefaultToSpeaker opt)   │
                         │    • RTCAudioSession (manual-audio mode)       │
                         │              │                                 │
                         │   ② POST /v1/session ─app JWT─▶ psybeam-worker  │──③ POST …/client_secrets
                         │   ④ {ek_, sdpUrl} ◀────────────(CF, real key)──│◀── ek_ (OpenAI)
                         │              │                                 │
                         │              ▼ ⑤ SDP handshake DIRECT          │
                         │   ════════════════════════════════════════════════▶ OpenAI gpt-realtime-translate
                         │   translated audio + transcript deltas ◀═══════════ (auto-detect src → output lang)
                         └────────────────────────────────────────────────┘
   Worker touches ONLY the one HTTPS mint round-trip. Real OpenAI key never leaves Cloudflare.
   Barge-in / turn-gating = local SpeechDetector(iOS 26) VAD → mute/unmute the WebRTC track + cancel server TTS.
```

**Why direct, not relayed (unchanged, confirmed):** relaying 24 kHz PCM through a Durable Object means full wall-clock DO billing (non-hibernatable outbound WS), a CF hop in the real-time path, and forfeiting WebRTC's Opus/FEC/jitter recovery — the exact robustness a traveler needs on flaky foreign cellular. The Worker only does the short HTTPS mint.

**Bidirectional = turn-gated single live direction, not two hot sessions.** VAD side-detection (LID narrowed to the two active languages) decides which direction to open; we mint/connect on turn-start, tear down on turn-end/idle-timeout. This halves the naive cost and removes the "translations firing on both sides at once" bug the review flagged. **Spike 3 measures whether per-turn connect latency is tolerable; if not, the fallback is one persistent session per direction with input muting (more cost, less latency) — decided by data, not now.**

---

## 4. THE iOS AUDIO LAYER (rewritten: WebRTC owns the session)

**The §4 of the prior design is deleted.** No hand-built `AVAudioEngine`, no `AVAudioConverter` 48↔24k, no `AVAudioPlayerNode` downlink, no jitter-buffer `CheckedContinuation`. WebRTC's `RTCAudioSession`/`audio_device_ios` owns capture, render, AEC, AGC, jitter buffer, Opus, and resampling. Fighting it produces one-way audio and silent reversion of the speaker route on ICE-connect — [verified failure mode](https://groups.google.com/g/discuss-webrtc/c/44ogyfkIC0w).

**`RealtimeCallService` (actor in `Psybeam`)** owns the `RTCPeerConnection` and coordinates the session:

- **Route control via category options, never `overrideOutputAudioPort`.** Loudspeaker (table mode) = set the `.defaultToSpeaker` category option through `RTCAudioSession`; earpiece/AirPods mode = clear it. This survives ICE-connect and honors user gestures (headset plug/unplug) — the manual override does not.
- **`RTCAudioSession.useManualAudio = true` + `isAudioEnabled`** to coordinate activation timing (mirrors the CallKit pattern even though we don't use CallKit — foreground-only, see below), so we activate the session deterministically and WebRTC doesn't race us.
- **Category/mode:** `.playAndRecord` / `.voiceChat` (WebRTC sets these itself; we don't fight it). VoiceProcessingIO is engaged by WebRTC → hardware AEC is the barge-in linchpin.
- **Bluetooth:** use **`.allowBluetoothHFP`** directly — it is the iOS 26 SDK rename of `.allowBluetooth`, a **new symbol that back-deploys to old iOS at runtime** ([Swift Forums](https://forums.swift.org/t/xcode-26-avaudiosession-categoryoptions-allowbluetoothhfp/80956), [Apple docs](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetoothhfp)). Since the **iOS 26 SDK is mandatory from Apr 28 2026** and we build only with Xcode 26, **no `#if` gate is needed** — the prior `#if compiler(>=6.2)` recommendation was wrong (that gates the *compiler*, not the SDK; and the symbol back-deploys so `#available` is wrong too). Add iOS 26 **`.bluetoothHighQualityRecording`** for AirPods/handset uplink.
- **Barge-in:** local VAD (`SpeechDetector`, iOS 26) fires while remote audio plays → **mute the local outbound track is wrong here**; instead **stop rendering the remote track / cancel in-flight server TTS** and ensure the inbound capture is clean (WebRTC AEC removes the device's own playback). The mechanism is track-level mute + a server `response.cancel`, not engine teardown.
- **Recovery:** on `mediaServicesWereResetNotification` and on ICE failure, tear down and rebuild the `RTCPeerConnection` (handled by the `reconnecting` state, §7).

**Foreground-only, no `audio` background mode for MVP** — it's a face-to-face tool; this also sidesteps an App Review question.

**Sendable surface (Combine removed from core):**
```swift
// PsybeamKit (pure, Sendable, Linux-compilable — NO AVFoundation, NO Combine)
public enum CallState: Sendable, Equatable {
    case idle, connecting, live(turn: Side), reconnecting, interrupted, ended, failed(CallError)
}
public protocol RealtimeCallProviding: Sendable {
    var states: AsyncStream<CallState> { get }          // AsyncStream, not AnyPublisher
    var transcripts: AsyncStream<TranscriptDelta> { get }
    func connect(spec: TranslationSessionSpec) async throws
    func setTurn(_ side: Side) async                    // gate active direction
    func bargeIn() async                                // cancel remote TTS
    func hangUp() async
}
```
```swift
// Psybeam target — the actor owns WebRTC; the VM adapts AsyncStream→Combine at the boundary
actor RealtimeCallService: RealtimeCallProviding {
    private let pc: RTCPeerConnection
    private let rtcSession = RTCAudioSession.sharedInstance()
    private let stateContinuation: AsyncStream<CallState>.Continuation
}
```
The `AsyncStream` continuation is `Sendable` and safe to yield from any executor — this **eliminates the §9-review `PassthroughSubject`-off-actor data-race hazard** entirely. The `@MainActor` VM consumes the stream in a `Task`, republishes to the VC via its **own** `PassthroughSubject<CallState, Never>` (Combine stays app-side, per conventions), and the VC binds in `viewDidLoad` with `.receive(on: DispatchQueue.main)` holding `Set<AnyCancellable>`.

---

## 5. THE CLOUDFLARE WORKER SURFACE (`psybeam-worker`, Hono v4 / jose v6)

> **VERIFIED 2026-06-07 (Spike 1) — implementation differs from the prose below; see §0.** The Worker mints at `POST /v1/realtime/translations/client_secrets` (body `{ session:{ model, audio.output.language } }`, no `type`) and returns `sdpUrl` `…/translations/calls`. **There is no output-language gate and no Azure 422 path** — both were removed; any requested language is minted. The "language gate / Azure path / 13-language list" steps below are historical.

**Bindings** (`wrangler.jsonc`): `KV: AUTH_NONCE` (Apple replay guard, 5m TTL), `KV: QUOTA` (per-user atomic minute ledger), `KV: SESSIONS` (concurrency + mint-rate guard), `D1: DB`. Secrets via `wrangler secret put` (`APPLE_CLIENT_ID`, `APP_JWT_SECRET`, `OPENAI_API_KEY`), `.dev.vars` locally. **No DO binding.** `OPENAI_TRANSLATE_OUTPUT_LANGS` is an informational `var` for `/v1/config` display only — never a gate, never compiled into the iOS binary.

**Three-layer gate (golf-coach parity):** SiwA `id_token` → verify via Apple JWKS (nonce replay-guarded in KV) → mint **HS256 app JWT (jose)** → every route requires it.
```
POST /v1/auth/apple      // SiwA id_token → app JWT
POST /v1/auth/refresh    // rotate app JWT (hourly)
GET  /v1/config          // GPS local lang → language gate + quota remaining
POST /v1/session         // CORE: gated mint of ek_ (per active direction)
POST /v1/session/usage   // advisory client report → reconcile ledger
GET  /v1/me/quota
```

**`POST /v1/session` — the broker, with the corrected abuse model:**
1. Verify app JWT → `userId`.
2. Validate target output lang against the server-side language list; ∈ list → OpenAI path, else → Azure path (422 if neither).
3. **Atomic KV debit at mint time** — `QUOTA` key `q:userId:yyyymmdd` decremented **before** returning the token, reject `429` if insufficient. Client-reported `/usage` is **advisory reconciliation only** (trivially spoofable). *This is the central fix to the review's #3.*
4. **Concurrency + rate guard:** `SESSIONS` enforces **≤2 concurrent sessions/user** and **a per-minute mint cap** (e.g. ≤6 mints/min). Bind each `ek_` to one `sessionId`.
5. Mint upstream with real key + `OpenAI-Safety-Identifier: sha256(sub)`:
```jsonc
{ "expires_after": { "anchor":"created_at", "seconds":120 },
  "session": { "model":"gpt-realtime-translate",
    "audio": { "input":{ "transcription":{ "model":"gpt-realtime-whisper" } },
               "output":{ "language":"es" } } } }   // output lang validated in step 2
```
6. Return `{ provider, ephemeralToken, expiresAt, sdpUrl:"https://api.openai.com/v1/realtime/calls", model, targetLanguage, maxSessionSeconds:3600, sessionId, minutesRemaining }`. iOS does the SDP exchange **directly**.

**Honest worst-case exposure.** Per *connected* session: bounded by the **60-min OpenAI hard cap** ≈ **$2.04** for translate. Per *leaked app JWT*: bounded by **`DAILY_QUOTA × $0.034` per user/day** — **only because** the debit is atomic-at-mint. Without atomic debit it is unbounded (the review's correct catch). Concurrency cap + mint rate-limit bound the burst.

**`GET /v1/config`** enforces the language ceiling server-side so the client never promises an unsupported pair, returning `{ localLanguage, translateSupported, recommendedPath, supportedOutputLangs, quota:{minutesRemaining} }`.

**KV/D1.** KV = hot atomic quota + nonce guard + concurrency. D1 = durable `users`/`sessions`/`usage_ledger` backstop and reconciliation source. **DO unused** (flagged-off code path for a hypothetical future relay-only provider).

---

## 6. LOCATION → LANGUAGE DESIGN

**MVP uses online `CLGeocoder` reverse-geocoding** for country→language (the review's #12 trim). The offline polygon engine is a **v1** feature — and it was *already* scoped to v1 for the no-signal path, so this just stops MVP from carrying it. Rationale: the "no bars at the border" case is real but rare, and reverse-geocoding the common case is one API call with zero bundle weight.

**The service.** `LocationLanguageService` is an `actor` in `Psybeam` wrapping `CLLocationManager`/`CLServiceSession`; the pure resolution logic (`CldrLanguageTable`, `LocaleSuggestion`, and — in v1 — the offline `PolygonCountryLocator`) lives in `PsybeamKit` and takes `(lat, lon)` or `(countryCode)` with **no CoreLocation import** (Linux-testable). Auth: **`whenInUse` only** (foreground tool; never `Always`, never `startUpdatingLocation`). One-shot foreground fix is the source of truth. Honor `.accuracyLimited`/`.locationUnavailable` → downgrade confidence near borders, suppress bad suggestions. **Do not depend on `CLMonitor` geofences for correctness** (documented unreliable across iOS 17–18; *not* a specific "26.1 regression," which was an unsupported claim — correctly walked back).

**v1 offline boundary approach (deferred, de-risked into Spike 5).** Bundle **Natural Earth 1:10m Admin-0** (public domain) for microstate correctness. **The review is right that a uniform-detail 1:10m file at a 1–4 MB target is not credible** — raw is ~20–25 MB. Resolution: **a hybrid layer** — coarse 1:50m for the common case + a **separate small enclave-only high-res layer** for the ~12 problem features (Vatican, San Marino, Büsingen, Llívia, Baarle, Monaco, Liechtenstein, Lesotho, Kaliningrad, Campione). This is smaller and faster than one uniformly-detailed file. **Bundle size and cold-start parse time are unverified → Spike 5 measures both before committing.** Runtime engine: pure-Swift ray-cast (Jordan-curve) + bbox pre-filter + nearest-polygon fallback — **NO GEOSwift/GEOS (LGPL static-linking trap)**; MIT GeoJSON parser at build time only.

**Country → language data (unchanged, curated).** Build-time script converts **CLDR 48 `territoryInfo.json`** (Unicode-3.0 license) into a **curated static `countryLanguages.json`**, ranked by `officialStatus` then population, **English-as-L2 suppressed** where it isn't the street language, 1–3 langs per ISO code (`"CH":["de","fr","it"]`, `"BE":["nl","fr"]`, `"CA":["en","fr"]`). The ranking is **editorial, not derivable** — hand-curate + test-fixture it. The app reads `Locale.preferredLanguages.first` on-device and **passes it explicitly** into the core (the core never reads `Locale` — env-dependent on Linux).

**Suggestion UX (unchanged).** GPS only **seeds the local-language target**; the model auto-detects spoken source. On country change → **non-blocking dismissible banner** (never modal): *"You've entered France 🇫🇷 — set local language to Français?"* → **[Set Français] [Choose another] [Not now]**. Auto-apply silently *only* if high-confidence AND user pre-enabled "switch automatically" (default **OFF**). Surface **endonym + flag** ("Français", not "French"). Recent-languages (last 5) + manual override are first-class; manual selection sticks until re-enabled or a border crossing (which still only *suggests*).

---

## 7. UX & STATE MACHINE

**Canonical `TranslationState`** (`PsybeamKit`, `nonisolated enum: Sendable`; the VM exposes exactly one `PassthroughSubject<TranslationState, Never>`, the VC subscribes once in `viewDidLoad`). **Expanded with the states the review found missing** — these *will* fire on foreign cellular and the clueless-local thesis demands each be visually legible, not a generic red triangle:
```swift
public enum Side: Sendable { case a, b }          // a = traveler (blue), b = local (green)
public enum TranslationState: Sendable, Equatable {
    case idle
    case armed(turn: Side)
    case listening(turn: Side, level: Float)
    case processing(from: Side)
    case speaking(to: Side, isReplay: Bool)
    case passthrough(side: Side)        // NEW: source already = target lang → model emits silence; show "same language" glyph, don't hang
    case reconnecting                   // NEW: ICE restart / ek_ expired mid-handshake / 60-min cap → transparent re-mint + handoff
    case quotaExhausted                 // NEW: free-tier minutes hit mid-conversation → what the LOCAL sees matters
    case permissionDenied(Permission)   // NEW: mic/location, distinct from error
    case offline
    case error(TranslationError)
}
```
State → presentation (no text required for the core loop): **idle** gray `globe` breathing · **armed** side-color `mic.fill .pulse` + `.medium` haptic + rising earcon · **listening** brightening `waveform .variableColor` driven by mic level · **processing** amber `arrow.triangle.2.circlepath .rotate` + streaming partial caption · **speaking** listener-color `speaker.wave.3.fill .variableColor + .bounce` + `.success` haptic + "ding" · **passthrough** neutral `equal.circle` + auto-translated "same language" chip · **reconnecting** amber `arrow.clockwise .rotate` (no alarm — this is routine) · **quotaExhausted** a gentle, *locally-translated* "session paused" card so the stranger isn't left confused · **permissionDenied** a targeted fix-this affordance · **offline** desaturated `wifi.slash` · **error** red `exclamationmark.triangle.fill .bounce` + `.error`. **The side-color contract is the only thing the stranger must learn — and they learn it in one cycle.**

**Table mode (default — BUT GATED by Spike 2).** Phone flat between two people, split screen, A-side container rotated 180° (`CGAffineTransform(rotationAngle: .pi)`) so the person across reads upright. Each half shows that person's own language (original on speaker's half, translation on listener's half, streaming deltas, Dynamic Type ≥`.title1`). **The entire half is one full-bleed `UIControl` tap target.** Caption cards on `UIVisualEffectView(effect: UIGlassEffect())` (tint per side, `isInteractive`), grouped in `UIGlassContainerEffect` (animate via the `effect` property, never `alpha`); iOS 18 fallback `.systemThinMaterial`.

**The echo caveat the review raised is real and now governs the rollout:** phone at loudspeaker on a hard table between two faces is the *worst* case for AEC double-talk and acoustic feedback in a noisy café/market. **Table mode ships as default ONLY if Spike 2 proves WebRTC's VPIO holds up in a noisy room with barge-in.** If it doesn't, the default flips to **handset/hold-to-talk** (a non-embarrassing, fully-designed path — not a second-class toggle) and table mode ships behind an explicit "Table mode" affordance with a "keep ~40 cm apart" hint and a duck-while-speaking gate.

**Handset/walkie mode (always shipped).** Upright, stacked blue "Me" / green "hand-over" buttons, default **hold-to-talk**. Corner glass `UISegmentedControl` flips Table ↔ Handset.

**Turn-taking default (Product Decision C, recommendation stands): hybrid auto-VAD with always-live half-tap override**, *contingent on Spike 2*. Auto-VAD in Table mode, side detection by **LID narrowed to the two active languages**, the active side **gates which WebRTC direction is live** (so we don't pay for or surface both). Half-tap *forces* `armed(turn:)` and locks the mic. Anti-collision: simultaneous triggers → turn-bar flashes amber, second speaker's half dims with a `down`-chevron `.pulse` = "wait."

**Clueless-local onboarding (<2 s, mostly wordless)** — unchanged and central: when the local's half first activates, a 3-element card auto-translated into the **GPS-detected local language**: (1) animated face + speech-bubble + `mic.fill .pulse` pictogram, (2) **one pre-translated line in their language** — *"Speak after the beep — I'll say it in their language"* — always in their tongue, (3) a big pulsing green `mic.fill`. Rising earcon on `armed`. **Trust chip says "encrypted" (auto-translated), NEVER "on-device"** — we are cloud; the claim must be honest.

**Bystander-consent gap (review #6b — genuinely unaddressed, now handled).** The *local never consented* to their voice going to OpenAI, and they cannot meaningfully consent. Mitigation: a **persistent, visible "translating via cloud AI" indicator on the local's half** (a small cloud glyph, auto-translated label), so the routing is disclosed visually to the bystander even though formal consent is impossible. This is the most we can honestly do and it should be in the App Review notes.

**THE FLAGSHIP INTERACTION — phased.** **MVP ships the *color contract*, not the fluid sim.** The bisecting divider is a `UIGlassContainerEffect` strip whose **tint and a simple directional color-fill** encode state: idle thin/centered/breathing; listening → the seam **fills with the speaker's color toward the listener**; processing → amber shimmer at center; speaking → the receiving half's color saturates + speaker icon bounces. This delivers the entire legibility payload (the local learns "blue→me, my words travel right") with a fraction of the engineering. **The full "Living Seam" droplet/pour fluid physics is a v1/Premium polish item** (review #12). **Engineering honesty preserved:** the divider's amplitude is driven by the **local mic level** (always available, zero latency), never the model output stream, so it never starves during the network tail. *The gap is still the feature — you still watch your words travel — just without a fluid solver in v1.*

---

## 8. DATA MODEL & CORE TYPES

**GRDB, on-device only — transcripts never leave the phone; this is the privacy moat.** **Deferred out of MVP** (review #12): history persistence is a v1 feature. MVP keeps the *current* conversation in memory only. When it lands, `nonisolated struct` records, `DatabaseMigrator.registerMigration("v1")`:
```swift
public struct Conversation: Codable, FetchableRecord, PersistableRecord, Sendable {
    public var id: Int64?; public var startedAt: Date; public var endedAt: Date?
    public var travelerLang: String; public var localLang: String
    public var countryCode: String?; public var provider: String   // "openai" | "azure" | "offline"
}
public struct Utterance: Codable, FetchableRecord, PersistableRecord, Sendable {
    public var id: Int64?; public var conversationId: Int64
    public var side: String; public var sourceText: String?; public var translatedText: String
    public var sourceLang: String; public var targetLang: String
    public var at: Date; public var isFavorite: Bool
}
public struct AppPreferences: Codable, FetchableRecord, PersistableRecord, Sendable {
    public var id: Int64?; public var travelerLang: String
    public var autoSuggestLocal: Bool; public var applyAutomatically: Bool   // default false
    public var aiConsentGranted: Bool; public var consentedAt: Date?          // 5.1.2(i)
    public var recentLangs: String                                           // CSV, last 5
}
```
`AppPreferences` (consent + prefs) ships in **MVP** even though conversation history doesn't — consent state must persist. Migrations: `v1` = these tables; `v2` adds `phrasebook`; `v3` multi-speaker. List cells: `UIBackgroundConfiguration.listCell()`.

**Sendable protocols `PsybeamKit` exposes — Combine removed, `AsyncStream` throughout** (review #10):
```swift
public protocol TranslationProviding: Sendable {
    func openSession(spec: TranslationSessionSpec) async throws -> TranslationSessionHandle
    var events: AsyncStream<TranslationEvent> { get }   // .audioDelta / .transcriptDelta / .turnEnded / .passthrough / .error
}
public protocol RealtimeCallProviding: Sendable { /* §4 */ }
public protocol LocationLanguageProviding: Sendable {
    var suggestions: AsyncStream<LanguageSuggestion> { get }
    func refreshOnForeground() async
    func resolve(countryCode: String, deviceLocale: String) -> LanguageSuggestion        // online MVP path
    func resolve(lat: Double, lon: Double, deviceLocale: String) -> LanguageSuggestion    // offline v1 path
}
public protocol Translating: Sendable {                 // offline MT bridge
    func translate(_ text: String, from: String?, to: String) async throws -> String
}
```
The `Translating` impl in `Psybeam` wraps a zero-size `UIHostingController` carrying SwiftUI `.translationTask` (the only way to get a `TranslationSession`) behind this Sendable protocol, keeping the rest of the app pure UIKit. All event/suggestion/spec types are `nonisolated`/`Sendable` value types → Linux-compilable, Swift-Testing-covered. **No `#if canImport(Combine)` fork anywhere in the core** — the protocol surface is now identical on macOS and Linux, so the test suite exercises the real shape.

---

## 9. PHASED ROADMAP (trimmed per review #12)

**MVP (Minimum Lovable) — the irreducible thesis, nothing more:**
- One-tap **turn-gated bidirectional** live translation via `gpt-realtime-translate`, **direct WebRTC** (WebRTC owns audio per §4).
- **Table mode** dual-facing, rotated, color-coded, large-type UI + **simple color-fill divider** (the color *contract*, not fluid physics). **Table-as-default gated on Spike 2**; handset/hold-to-talk fully designed as the fallback default.
- **Online `CLGeocoder`** GPS language suggestion + CLDR table, endonym banner, manual override + recents. (Offline polygon engine deferred to v1.)
- Sign-in-with-Apple → app JWT → Worker mint; **atomic** free tier **10 min/day** (KV).
- **5.1.2(i) pre-audio consent screen + revocable Settings toggle** (revocation actually kills cloud routing) naming OpenAI + Cloudflare; **bystander "cloud AI" indicator** on the local's half; privacy-policy update.
- **4.3 defense baked into the submission:** first screenshot = the dual-facing table moment; App Review notes lead with the differentiation.
- Privacy Manifest (`CA92.1`; `7D9E.1` DiskSpace if GRDB ships), `ITSAppUsesNonExemptEncryption=false`.
- StoreKit 2 monthly ($9.99) + annual ($59.99) + 7-day trial. **Consent persistence in GRDB `AppPreferences`.** (Conversation history, Live Activity, Action Button deferred.)

**v1:**
- **Azure Live Interpreter fallback** for non-13 output corridors (Arabic/Thai/Turkish/Greek) + Personal Voice (pending Limited-Access approval applied-for on day 1).
- **Offline mode** (SpeechAnalyzer → TranslationSession → AVSpeechSynthesizer) + the **hybrid offline polygon engine** (coarse + enclave layer, Spike 5).
- On-device **conversation history (GRDB)**, **Live Activity**, **Action Button**, Control Center control, Lock-Screen widget, Siri/Shortcuts.
- **Trip-pack consumables priced against 2× COGS worst case** ($19.99/300 min, $34.99/600 min), win-back, offer codes; server-side entitlement verification (`appTransactionID` + App Store Server API).
- **Full "Living Seam" fluid physics** as the signature polish.

**Premium / v2:**
- Apple Watch companion (bolsters 3.1.2 ongoing-value defense). BYO-key Pro tier (*verify OpenAI ToS on end-user-key proxying first*). Conversation export, phrasebook, multi-speaker labels. Output-gap chain (Azure/Qwen3-Omni self-host) for the deepest exotic-output corridors.

---

## 10. TOP RISKS & PRODUCT DECISIONS THE USER MUST MAKE

**Top risks (each maps to a resolution or a spike):**
1. **13-output-language ceiling.** OpenAI can't *speak* Arabic/Thai/Turkish/Greek/Polish/Dutch/Hebrew — the frequent-traveler corridors. Mitigation: Azure fallback (Limited-Access, apply day 1) + **read-mode** (show translated *text* to the local even when speech-out is unavailable — still serves "the local sees it"). **The exact 13-list is unverified → Spike 1, server-config not hardcoded.**
2. **App Review — three fronts.** **4.3 Spam** (NEW, the most common translation-app rejection — [Apple guidelines](https://developer.apple.com/app-store/review/guidelines/), [4.3 thread](https://developer.apple.com/forums/thread/112848)): foreground the table/divider differentiation in screenshots + review notes, never resubmit a near-duplicate. **5.1.2(i)** consent (pre-audio, revocable, policy update — [Nov 13 2025 tightening](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai/)). **3.1.2** ongoing value (model/language updates, offline packs, Watch, Live Activity defend it).
3. **Table-mode echo/feedback** (review #2) — untested physics; **gated on Spike 2**, with a designed handset fallback default.
4. **Abuse via leaked app JWT** (review #3) — resolved by **atomic-at-mint KV debit** + concurrency cap + mint rate-limit. Per-session bounded by the real 60-min cap.
5. **Latency on foreign cellular** — P90 TTFA unpublished; WebRTC is the hedge; **Spike 4 instruments mouth-to-ear on real cellular** before locking turn-gating vs. persistent-session.
6. **Privacy-claim honesty** — cloud, never "on-device" for the live path; **"never used for training" is unverified — do not claim ZDR** until OpenAI's terms for `gpt-realtime-translate` are confirmed in writing. Bystander cannot consent → visible cloud indicator is the honest floor.
7. **COGS uncertainty** — re-derived to $12–22/trip (turn-gated), but real silence/turn overhead is **unmeasured → Spike 3**; trip-packs priced against 2× worst case.
8. **iOS 26 SDK mandatory Apr 28 2026** (Liquid Glass default-on — budget UI testing); EU fee stack (factor into EU margin).
9. **Offline bundle size/parse** (review #7) — 1–4 MB at uniform 1:10m is not credible; **hybrid coarse+enclave layer → Spike 5 measures** before committing.

**Product decisions the user must make before building:**
- **A. Backend cost posture.** Ship OpenAI-primary (best UX) accepting the 13-lang gap for MVP, Azure in v1 — **apply for Azure Limited Access today** (long pole). *(Recommended.)*
- **B. Monetization.** Confirm hybrid: free 10 min/day + sub ($9.99/$59.99) + v1 trip-packs ($19.99/$34.99). Ship BYO-key Pro? (needs OpenAI ToS confirmation — defer).
- **C. Turn-taking default.** Confirm **auto-VAD-with-tap-override** (recommended) — but it is **contingent on Spike 2**; if table mode fails the noisy-room test, the default becomes **push-to-talk handset**. This is now a data-driven decision, not a pre-commitment.
- **D. Offline scope.** Confirmed **v1**, not MVP (MVP uses `CLGeocoder`).
- **E. The name.** **Psybeam** (my pick) or **Borderless**. Verify .app/.com + USPTO/EUIPO before committing. Avoid Babel/Babble (trademark thicket).

---

## 11. SPIKES TO RUN FIRST

The five smallest experiments that validate the load-bearing assumptions. **Run before writing the code each gates. Each has a binary pass/fail and a fallback.**

**Spike 1 — Verify the real output-language list + the mint contract (½ day, gates §2/§5).**
From a throwaway script, hit the live OpenAI translate model/docs endpoint and **enumerate the actual 13 output languages**; mint an `ek_` from a minimal Worker and confirm the `output.language` codes that are accepted (try `ar`, `th`, `tr` — expect rejection; confirm which of ES/PT/FR/JA/RU/ZH/DE/KO/HI/ID/VI/IT/EN are accepted). **Pass:** list confirmed, Worker stores it as `var`. **Fail/blocked:** keep the list server-config and ship a "languages we speak" screen driven by `/v1/config`. *Validates the entire corridor-coverage thesis and de-risks the one fact no secondary source confirms.*

**Spike 2 — Table-mode echo & barge-in on real hardware in a noisy room (1–2 days, gates §7 default + Product Decision C).**
iPhone Air flat on a hard table, loudspeaker, two people ~40 cm apart, café-level background noise. Run a real `gpt-realtime-translate` WebRTC session; have person B barge-in while the phone is speaking person A's translation. **Pass:** WebRTC VPIO suppresses self-echo, no runaway feedback, barge-in is clean → **table mode ships as default**. **Fail:** default flips to handset/hold-to-talk; table mode ships behind a hint + duck-gate. *This is the single biggest product-feel risk and it cannot be reasoned about — only measured.*

**Spike 3 — Turn-gated vs. persistent-session cost & latency (1 day, gates §3 bidirectional design + COGS).**
Implement both: (a) mint/connect-per-turn, tear down on idle; (b) one persistent session per direction with input muting. Run a scripted 5-minute bilingual conversation on each, measure **wall-clock billed minutes** and **per-turn connect latency**. **Pass (a):** per-turn connect latency tolerable (<~700 ms perceived) → ship turn-gated, lower COGS. **Pass (b) only:** ship persistent + muting, re-price. *Resolves the review's 2× COGS catch and the "translations on both sides" bug with data.*

**Spike 4 — End-to-end mouth-to-ear latency on real foreign-grade cellular (1 day, gates the §7 divider timing + the WebRTC-vs-WS choice confidence).**
Mint `ek_` from the Worker, connect iOS→OpenAI **direct WebRTC** over a throttled/real cellular link (Network Link Conditioner "3G"/"LTE-lossy" + a real SIM if possible), measure P50/P90 **mouth-to-ear**. **Pass:** P90 acceptable for face-to-face turn-taking; confirms WebRTC's FEC/jitter earns its keep. **Fail:** investigate regional TURN/relay or accept higher latency. *Confirms the core robustness claim that justified WebRTC over WebSocket.*

**Spike 5 — Offline boundary bundle size + cold-start parse (½–1 day, gates the v1 offline geocoder; run before v1, not MVP).**
Build the hybrid layer (1:50m coarse + enclave-only 1:10m for the ~12 problem features), emit the compact binary, **measure bundle bytes and cold deserialization + first-fix time** on an iPhone Air. Test the enclave fixtures (Büsingen, Llívia, Baarle, Vatican, Campione, Kaliningrad). **Pass:** bundle ≤ ~6 MB and parse < ~150 ms. **Fail:** lazy-load the enclave layer or fall back to `CLGeocoder`-only with a "no offline near borders" note. *Replaces the non-credible 1–4 MB uniform-1:10m target with a measured number.*

**Sequencing:** Spikes 1, 2, 4 are the MVP go/no-go set and can run in parallel in week 1. Spike 3 follows once a basic WebRTC loop exists. Spike 5 is v1-time. **Do not write §4 audio code before Spike 2 passes, and do not lock the turn-taking model before Spike 3.**

---

**Sources:** [gpt-realtime-translate model](https://developers.openai.com/api/docs/models/gpt-realtime-translate) · [OpenAI voice-models announcement](https://openai.com/index/advancing-voice-intelligence-with-new-models-in-the-api/) · [9to5Mac coverage](https://9to5mac.com/2026/05/07/openai-has-new-voice-models-that-reason-translate-and-transcribe-as-you-speak/) · [Brockman 70→13](https://x.com/gdb/status/2060452095279415725) · [Realtime 60-min session cap (GA)](https://developers.openai.com/blog/realtime-api) · [expires_after vs. session lifetime](https://community.openai.com/t/how-to-limit-openai-realtime-api-sessions-to-x-minutes-max/1365611) · [WebRTC owns AVAudioSession / speaker reverts on connect](https://groups.google.com/g/discuss-webrtc/c/44ogyfkIC0w) · [allowBluetoothHFP rename (Swift Forums)](https://forums.swift.org/t/xcode-26-avaudiosession-categoryoptions-allowbluetoothhfp/80956) · [allowBluetoothHFP (Apple docs)](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetoothhfp) · [App Review Guidelines (4.3, 3.1.2, 5.1.2)](https://developer.apple.com/app-store/review/guidelines/) · [4.3 spam rejection thread](https://developer.apple.com/forums/thread/112848) · [5.1.2(i) third-party-AI consent, Nov 13 2025](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai/)

**Explicitly unverified, flagged for spikes:** the exact 13 output-language enumeration (Spike 1); P90 mouth-to-ear latency on cellular (Spike 4); real silence/turn COGS overhead (Spike 3); table-mode AEC behavior in a noisy room (Spike 2); offline bundle size/parse (Spike 5); current Azure Live Interpreter / Personal Voice Limited-Access approval timeline; OpenAI ZDR/no-training terms for `gpt-realtime-translate`; OpenAI ToS stance on end-user-key proxying for the BYO-key tier.