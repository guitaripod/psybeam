# Psybeam

[![CI](https://github.com/guitaripod/psybeam/actions/workflows/ci.yml/badge.svg)](https://github.com/guitaripod/psybeam/actions/workflows/ci.yml)

A real-time voice-to-voice travel interpreter for iOS. You hold the phone and you're the only operator: two thumb-buttons — your language and theirs. Hold yours to speak and it speaks their language aloud to the person across from you; hold theirs while they reply and it speaks yours back. The stranger never has to touch the phone or understand the UI — the audio carries it, and when it's their turn the screen invites them to speak in their own language. The translation always faces whoever it's for. The local language auto-suggests by GPS as you cross borders.

> Built for the person handed the phone, not the owner.

## How it works

Speech is translated by OpenAI's `gpt-realtime-translate` (simultaneous speech-to-speech — it auto-detects the source, mimics the speaker's voice, and streams the result) over **WebRTC directly from the device**. A Cloudflare Worker mints short-lived ephemeral tokens so the real OpenAI key never leaves Cloudflare and the audio never touches our own infrastructure. Each direction is its own turn-gated session sharing one microphone.

## Structure

Two parts in this repo, plus a shared backend:

- **`Sources/PsybeamKit`** — platform-agnostic Swift 6 core: the `TranslationState`/`Side`/`CallState` state machine, `Sendable` provider protocols exposing `AsyncStream`, DTOs, and the CLDR locale tables. No UIKit/AVFoundation. Compiles and tests on Linux and macOS.
- **`Psybeam/`** — the programmatic UIKit app (xcodegen, no storyboards). MVVM with Combine only at the VM↔VC seam, a Metal aurora that reacts to the voice, Sign in with Apple, Liquid Glass. iOS 18+ deploy target, iOS 26 SDK, iPhone-only.

The backend is **mako** — a shared Cloudflare Worker (`mako.midgarcorp.cc`, repo `guitaripod/pixie`) that mints the ephemeral OpenAI token, meters minutes as credits, and handles Sign in with Apple. It lives outside this repo.

See **[DESIGN.md](DESIGN.md)** for the architecture, the state machine, the data model, and the spikes that gate the build.

## Build

```bash
scripts/setup.sh         # one-time: .env.local + xcodegen + SPM resolve
scripts/ios-build.sh     # device build
scripts/ios-deploy.sh    # build + install + relaunch on your device
```

`scripts/setup.sh` creates the gitignored `.env.local` you supply yourself (your bundle id, team id, device udid — see `.env.local.example`). The app ships no API keys: all backend secrets (the OpenAI key, etc.) live on the shared mako worker, not in this repo.

## Stack

Swift 6 strict concurrency · UIKit (programmatic) · Combine · GRDB · Metal · WebRTC ([stasel/WebRTC](https://github.com/stasel/WebRTC)) · OpenAI `gpt-realtime-translate` · mako credits backend (shared Cloudflare Worker) · Sign in with Apple.
