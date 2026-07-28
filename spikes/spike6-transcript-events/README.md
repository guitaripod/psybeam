# Spike 6 — what `/v1/realtime/translations` actually emits

**Status: RESOLVED — 2026-07-29.** Run live against the real API. Six full sessions
(one per candidate input-transcription model), synthesized English speech followed by
up to 8 s of trailing silence and a 20 s watch window.

Triggered by OpenAI's 2026-07-28 transcription release (`gpt-live-transcribe`,
`gpt-transcribe`). Those models are ASR only — **they do not replace
`gpt-realtime-translate`**, which remains the primary and is untouched by that release.
The spike checked whether they change anything for Psybeam. Two findings did.

## Findings

1. **No input transcription is configured → zero `input_transcript` events.** The mint
   echoes `"transcription": null` and the session emits only
   `session.output_transcript.delta` + `session.output_audio.delta`. The app's
   source-confirmation line (`sourceLabel`, fed by `TranslationLeg.sourcePublisher`)
   therefore had **no data source at all** until mako started sending one.

2. **The transport never closes a turn.** Across every run — including 8 s of trailing
   silence and 20 s of watching afterwards — **no `.done`, `.completed`, or any other
   closing event ever arrived**. Only `.delta`. `RealtimeCallService`'s
   `type.hasSuffix(".done")` was consequently always false, so `TranscriptDelta.isFinal`
   was never true, `TranslationLeg.finishedPublisher` never fired, and
   `onTurnFinished()` — success haptic, completion animation, and
   `ReviewPrompt.recordCompletedTurn` — never ran. `TranslationLeg` now closes a turn on
   caption quiescence (1.2 s after the last delta, only once the hold is released);
   measured worst-case inter-delta gap was 1235 ms, p90 ~400–600 ms.

3. **Every transcription model is accepted; only one streams.** All five emit the same
   final source text on clean speech, but the delivery differs sharply:

   | model | $/min | first delta | delivery |
   |---|---|---|---|
   | `gpt-live-transcribe` | 0.017 | 2391 ms (mid-speech) | true incremental streaming |
   | `gpt-4o-transcribe` | 0.006 | 6184 ms | one burst at end of turn |
   | `gpt-4o-mini-transcribe` | **0.003** | 6314 ms | one burst at end of turn |
   | `gpt-transcribe` | 0.0045 | 7819 ms | one burst at end of turn |
   | `whisper-1` | 0.006 | 6526 ms | single delta, whole string |

   **Shipped: `gpt-4o-mini-transcribe`** — the source line is a display-only
   confirmation that never affects translation quality, so +$0.003/min (+9% on the
   $0.034/min translate rate) buys the same text that `gpt-live-transcribe` charges
   +$0.017/min (+50%) for. The one thing the extra buys is a source line that fills in
   while you speak instead of landing complete ~1.4 s after you stop.

4. **The context-ASR knobs from the announcement are rejected here.** `prompt`,
   `keywords`, `language`, and `languages` all 400 with `Unknown parameter` under
   `session.audio.input.transcription` — they exist only in a dedicated
   `/v1/realtime/transcription_sessions`. So the accuracy tuning OpenAI advertised
   (free-form context, name/term keywords, expected languages) is **not reachable** from
   a translations session. `session.audio.output.voice` is rejected too.

5. **`session.audio.input.noise_reduction: {"type":"near_field"}` IS accepted** and
   currently unset. Untested for effect — Apple's VPIO already runs AEC/NS on-device, so
   stacking server-side NR may not help. A lever for Spike 2, not a shipped default.

## What changed in the code

- **mako** `src/handlers/realtime.rs` — mint body now sends
  `audio.input.transcription.model = gpt-4o-mini-transcribe`.
- `Psybeam/Conversation/TranslationLeg.swift` — `scheduleSettle()`/`finishTurn()` close a
  turn on quiescence; `settleInterval` is injectable so tests don't sleep for real.
- `Psybeam/Services/RealtimeCallService.swift` — `isTurnFinal(_:)` extracted and
  documented as forward compatibility only.

## Re-running

```bash
./run.sh                       # all six models
./run.sh --silence=12 --wait=30    # hunt harder for a closing event
node probe.mjs --transcribe=gpt-live-transcribe --lang=fi
```

Requires `node` (global `WebSocket`, Node 22+), plus `say` + `ffmpeg` the first time to
synthesize the speech clip. Note the `openai-beta.realtime-v1` WebSocket subprotocol is
now rejected outright (`beta_api_shape_disabled`) — connect with only `realtime` and
`openai-insecure-api-key.<ek_>`.
