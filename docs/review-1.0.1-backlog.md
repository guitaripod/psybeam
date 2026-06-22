# Psybeam code-review backlog (workflow w3nu60x3g, 2026-06-22)

51 findings, each adversarially verified (isReal=true). Applied in 1.0.1: #1 TalkButton both-buttons `isExclusiveTouch`, #19 mic-denial feedback, #42 brightness restore. The unverified no-training claim was already removed.

| sev | safe | lane | file | issue |
|---|---|---|---|---|
| high | careful | audio-webrtc | `Psybeam/Services/RealtimeCallService.swift:240` | No AVAudioSession interruption handling — a phone call/Siri/alarm permanently breaks the live session |
| high | careful | audio-webrtc | `Psybeam/Services/RealtimeCallService.swift:243` | No route-change handling — unplugging headphones/Bluetooth mid-turn leaves the mic live with no UX response |
| high | careful | audio-webrtc | `Psybeam/Conversation/ConversationViewController.swift:638` | First-launch mic-permission denial during the initial hold is swallowed — user holds into a dead mic with no feedback |
| high | yes | compliance | `Psybeam/Consent/ConsentViewController.swift:41` | Consent + Settings claim OpenAI "isn't used to train AI models" — the exact ZDR/no-training claim DESIGN.md forbids until confirmed in writing |
| high | careful | compliance | `Psybeam/Conversation/ConversationViewController.swift:379` | Cloud-AI bystander indicator faces the operator, not the local — violates the DESIGN.md 'on the local's half' honest-floor requirement |
| high | careful | concurrency | `Psybeam/Services/RealtimeCallService.swift:48` | AsyncStream continuations are never finished, leaking the three observer Tasks for every TranslationLeg / call instance |
| high | careful | concurrency | `Psybeam/Conversation/TranslationLeg.swift:121` | `ensureConnected` is re-entrant on the @MainActor: the in-flight-task guard has an await gap that lets a second caller spawn a duplicate connect |
| high | yes | correctness | `Psybeam/Conversation/TalkButton.swift:79` | Both talk buttons can be held at once; the force-released button stays visually "active" (mic pulsing, glow) with no way to reset |
| high | careful | services-data | `Psybeam/Services/CreditsTranslationProvider.swift:40` | Concurrent legs overwrite the single pendingSessionId slot — one reservation is never refunded after a kill |
| high | careful | services-data | `Psybeam/Services/CreditsTranslationProvider.swift:79` | registerStart() resets the conversation total to zero while the other leg is still mid-conversation — corrupts cross-leg minute accounting |
| high | careful | services-data | `Psybeam/Settings/SettingsViewController.swift:516` | Account-deletion wipe leaves real user state behind — languages and other settings survive 'erase on-device data' |
| high | careful | ux-a11y | `Psybeam/Conversation/TalkButton.swift:60` | Hold-to-talk buttons are unusable under VoiceOver — double-tap fires down+up instantly |
| high | careful | ux-a11y | `Psybeam/Conversation/ConversationViewController.swift:268` | Translation output is never announced or exposed to VoiceOver — blind operator gets nothing |
| high | careful | ux-a11y | `Psybeam/Conversation/ConversationViewController.swift:611` | Reduce Motion is ignored everywhere — pulse, 180° flip, spring settle, and aurora all animate unconditionally |
| high | careful | ux-a11y | `Psybeam/Conversation/ConversationViewController.swift:468` | Dynamic Type is effectively dead: fixed point sizes, and status/source labels never opt in |
| medium | careful | audio-webrtc | `Psybeam/Conversation/ConversationViewController.swift:528` | TalkButton latches into the active/pulsing state even when the hold is rejected (consent gate or mic denied) |
| medium | careful | audio-webrtc | `Psybeam/Conversation/ConversationViewController.swift:177` | didEnterBackground ends the session but resigning-active (e.g. control center / call banner) does not, risking capture loss without state update |
| medium | yes | compliance | `Psybeam/Conversation/ConversationViewController.swift:516` | Cloud-AI badge is hardcoded English 'Cloud AI' — DESIGN requires it auto-translated into the local's language for the bystander |
| medium | careful | compliance | `Psybeam/Consent/ConsentViewController.swift:41` | Consent screen names only OpenAI; Cloudflare (the token broker holding the real key) is undisclosed despite DESIGN requiring both named |
| medium | yes | compliance | `Psybeam/Settings/SettingsViewController.swift:470` | Withdrawing consent gives no confirmation and silently kills the session, leaving an inert screen — fails the 'revocation actually works and is legible' bar |
| medium | careful | concurrency | `Psybeam/Services/RealtimeCallService.swift:38` | Unbounded AsyncStream continuations never set a buffering policy, so transcript/level/state backpressure accumulates without bound |
| medium | careful | concurrency | `Psybeam/Services/RealtimeCallService.swift:135` | Mic-off does not reset the level stream, so the waveform freezes at the last live amplitude instead of falling to zero |
| medium | yes | concurrency | `Psybeam/Conversation/TranslationLeg.swift:59` | `holdDown` reads `self.holding` inside a delayed Task without re-checking that the same hold gesture is still active, racing a fast hold/release/hold |
| medium | careful | concurrency | `Psybeam/Conversation/TranslationLeg.swift:197` | `reconnectTimer` deadline fires `call.hangUp()` but never clears the in-flight `connectTask`, and can run concurrently with a fresh connect |
| medium | careful | concurrency | `Psybeam/Services/LocationLanguageService.swift:41` | `LocationLanguageService` reverse-geocode result is never deduplicated and `detected` fires on every CL update, re-triggering language re-mints |
| medium | yes | concurrency | `Psybeam/Services/LocationLanguageService.swift:31` | CLGeocoder is invoked from concurrent Tasks; Apple documents one in-flight geocode per CLGeocoder instance, so overlapping fixes cancel each other |
| medium | yes | concurrency | `Psybeam/Services/CreditsTranslationProvider.swift:91` | `CreditsTranslationProvider.accrue` decrements `openSessions` as a side effect inside the billing-math method, so an early connect failure permanently desyncs the open-session counter |
| medium | careful | correctness | `Psybeam/Conversation/TranslationLeg.swift:197` | Reconnect-deadline failure path can fire after the user already released the button, but holdDown's listening state can re-arm a dead peer |
| medium | yes | correctness | `Psybeam/Conversation/ConversationViewController.swift:184` | didBecomeActive re-warms and un-pauses the visualizer unconditionally, but didEnterBackground called viewModel.end() — the warm session is gone and mic permission UI can be stuck |
| medium | careful | correctness | `Psybeam/Conversation/WaveVisualizerView.swift:48` | Metal-unavailable fatalError on a real (low-power / GPU-denied) device path crashes at launch |
| medium | yes | correctness | `Psybeam/Conversation/ConversationViewController.swift:637` | requestMicPermission ignores the result; a first-launch denial leaves the user on a live-looking screen with no guidance until they hold a button |
| medium | careful | services-data | `Psybeam/Database/AppPreferences.swift:4` | AppPreferences GRDB record and its table are entirely dead — defined, migrated, never read or written |
| medium | yes | services-data | `Psybeam/Services/KeychainStore.swift:30` | KeychainStore silently ignores all Security errors and is itself unused dead code |
| medium | yes | services-data | `Psybeam/Services/CreditsTranslationProvider.swift:102` | settle() never clears a pending entry when the settled session isn't the currently-pending one, and silently swallows settle failures with no retry |
| medium | careful | services-data | `Psybeam/Database/DatabaseManager.swift:24` | DatabaseManager fails hard with fatalError on any init error — a corrupt or unwritable store bricks every launch |
| medium | yes | ux-a11y | `Psybeam/Conversation/ConversationViewController.swift:259` | Rotated their-language caption has no accessibilityLanguage — VoiceOver reads foreign text with the wrong synthesizer |
| medium | careful | ux-a11y | `Psybeam/Conversation/ConversationViewController.swift:620` | Talk button accessibilityLabel omits the side/hint, so the two buttons are indistinguishable by role |
| medium | careful | ux-a11y | `Psybeam/Conversation/ConversationViewController.swift:213` | Out-of-credits store sheet auto-presents from a render path and can be dismissed back into a dead session |
| medium | careful | ux-a11y | `Psybeam/Conversation/TalkButton.swift:39` | Low-contrast text on the moving aurora fails legibility for secondary captions |
| medium | careful | ux-a11y | `Psybeam/Conversation/ConversationViewController.swift:643` | Mic-permission-denied recovery only fires on app foreground, not on Settings round-trip or live grant |
| medium | careful | ux-a11y | `Psybeam/Conversation/ConversationViewController.swift:306` | Consent decline ('Not now') leaves the user on a black, dead conversation screen with no path forward |
| low | careful | compliance | `Psybeam/Settings/SettingsViewController.swift:174` | Settings privacy disclosure omits the Cloud-AI indicator's bystander rationale and is operator-only — the bystander disclosure lives nowhere reviewable in Settings |
| low | careful | concurrency | `Psybeam/Services/RealtimeCallService.swift:290` | `CallCoordinator` (@unchecked Sendable) calls `JSONDecoder().decode` and yields to the actor's continuation directly from the WebRTC signaling thread, but `direction` and the conts are immutable — verify no transcript ordering inversion |
| low | careful | concurrency | `Psybeam/Services/NetworkMonitor.swift:13` | `NetworkMonitor.isOnline` defaults to `true` before `start()` and before the first path update, so early failures are mislabeled as on-network errors instead of offline |
| low | yes | correctness | `Psybeam/Conversation/ConversationViewController.swift:75` | Idle timer / max brightness never restored when the VC's window resigns key for a non-background reason; savedBrightness captured once and stale |
| low | yes | correctness | `Psybeam/Conversation/TranslationLeg.swift:210` | Leg's accumulated source/text never reset on .ended/.failed, so a stale source line can bleed into the next session |
| low | careful | correctness | `Psybeam/Conversation/ConversationViewController.swift:658` | speakPrompt/endonym fall back to English-only strings; prompt map omits several of the app's own 22 supported languages |
| low | careful | correctness | `Psybeam/Conversation/ConversationViewController.swift:203` | Earcon chime + visualizer bloom fire on the local leg's .listening, which the warm path re-emits — risk of chime on warm-up, not just on the local's turn |
| low | careful | ux-a11y | `Psybeam/Settings/SettingsViewController.swift:69` | Per-second mic-mode polling timer with no VoiceOver update and redundant work |
| low | careful | ux-a11y | `Psybeam/Settings/SettingsViewController.swift:274` | Settings cards, rows, and section headers expose no accessibility grouping; toggle rows aren't labeled as a unit |
| low | yes | ux-a11y | `Psybeam/Conversation/ConversationViewController.swift:195` | Haptics fire on every Settings toggle but error/quota/offline states in the conversation have no haptic |
