# Psybeam

A voice-to-voice travel interpreter for iPhone. You hold the phone and press one of two buttons: yours or theirs. Hold yours and speak, and Psybeam says it aloud in the other person's language. Hold theirs while they answer, and you hear it in yours. The other person never touches the phone; when it is their turn the screen asks them, in their language, to speak. The local language is suggested from GPS as you cross borders.

## How it works

Speech goes to OpenAI's `gpt-realtime-translate` (simultaneous speech to speech: it detects the source language, keeps the speaker's voice and streams the result) over WebRTC, straight from the device. The app ships no API key. Midgar's intelligence service (`services/intelligence`, behind `api.midgarcorp.cc/v1/intelligence`) mints a short-lived token for each session and meters the minutes as credits from the person's Midgar ID wallet. Audio never passes through Midgar's servers. Credit packs are App Store purchases.

## Layout

```
Core/PsybeamCore/     Swift 6 package: the turn and call state machines, provider protocols, CLDR locale tables (builds on Linux)
App/ Features/        programmatic UIKit app (XcodeGen, MVVM), Metal aurora that follows the voice, Liquid Glass
Resources/            string catalog, assets, privacy manifest
Tests/                unit and StoreKit tests
```

[DESIGN.md](DESIGN.md) has the architecture and the state machine.

## Build

iOS 18 or later, iPhone. MidgarKit and AICredits are local packages in the Midgar monorepo (`packages/`).

```
scripts/setup.sh        # once: .env.local (bundle id, team id, device), xcodegen, package resolve
scripts/ios-build.sh    # device build
scripts/ios-deploy.sh   # build, install and launch on your device
scripts/ios-test.sh
swift test --package-path Core/PsybeamCore
```
