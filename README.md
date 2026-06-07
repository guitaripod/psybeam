# Psybeam

[![CI](https://github.com/guitaripod/psybeam/actions/workflows/ci.yml/badge.svg)](https://github.com/guitaripod/psybeam/actions/workflows/ci.yml)

A real-time voice-to-voice travel interpreter for iOS. You hold the phone and you're the only operator: two thumb-buttons — your language and theirs. Hold yours to speak and it speaks their language aloud to the person across from you; hold theirs while they reply and it speaks yours back. The stranger never has to touch the phone or understand the UI — the audio carries it, and when it's their turn the screen invites them to speak in their own language. The translation always faces whoever it's for. The local language auto-suggests by GPS as you cross borders.

> Built for the person handed the phone, not the owner.

## How it works

Speech is translated by OpenAI's `gpt-realtime-translate` (simultaneous speech-to-speech — it auto-detects the source, mimics the speaker's voice, and streams the result) over **WebRTC directly from the device**. A Cloudflare Worker mints short-lived ephemeral tokens so the real OpenAI key never leaves Cloudflare and the audio never touches our own infrastructure. Each direction is its own turn-gated session sharing one microphone.

## Structure

Three parts, mirroring the rest of these apps:

- **`Sources/PsybeamKit`** — platform-agnostic Swift 6 core: the `TranslationState`/`Side`/`CallState` state machine, `Sendable` provider protocols exposing `AsyncStream`, DTOs, and the CLDR locale tables. No UIKit/AVFoundation. Compiles and tests on Linux and macOS.
- **`Psybeam/`** — the programmatic UIKit app (xcodegen, no storyboards). MVVM with Combine only at the VM↔VC seam, a Metal aurora that reacts to the voice, Sign in with Apple, Liquid Glass. iOS 18+ deploy target, iOS 26 SDK, iPhone-only.
- **`workers/`** — the Cloudflare Worker (Hono, jose, KV + D1): Sign in with Apple → app JWT, ephemeral token mint, atomic per-user minute quota, usage ledger.

See **[DESIGN.md](DESIGN.md)** for the architecture, the state machine, the data model, and the spikes that gate the build.

## Build

```bash
scripts/setup.sh         # one-time: .env.local + Secrets.swift + xcodegen + SPM resolve
scripts/ios-build.sh     # device build
scripts/ios-deploy.sh    # build + install + relaunch on your device

cd workers
npm install
npm run typecheck && npm test
npx wrangler deploy
```

`scripts/setup.sh` creates the two gitignored files you supply yourself: `.env.local` (your bundle id, team id, device udid — see `.env.local.example`) and `Psybeam/Secrets.swift` (your Worker URL — see `Psybeam/Secrets.example.swift`). Worker secrets (`OPENAI_API_KEY`, `APP_JWT_SECRET`, `APPLE_CLIENT_ID`, `APPLE_TEAM_ID`) are set with `wrangler secret put`; see `workers/.dev.vars.example`.

## Stack

Swift 6 strict concurrency · UIKit (programmatic) · Combine · GRDB · Metal · WebRTC ([stasel/WebRTC](https://github.com/stasel/WebRTC)) · OpenAI `gpt-realtime-translate` · Cloudflare Workers (Hono · jose · KV · D1) · Sign in with Apple.
