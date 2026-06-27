# Spike 1 — `gpt-realtime-translate` mint contract + output-language coverage

**Status: RESOLVED — 2026-06-07.** Run live against the real API with a working key.

Gates DESIGN §2 (backend) and §5 (Worker mint). The spike set out to confirm the
"~13 speakable languages" ceiling and the mint shape. It found something more important:
**the model is served on a different endpoint than the docs/scaffold assumed, and there
is no 13-language ceiling.**

## Findings

1. **Dedicated namespace.** `gpt-realtime-translate` is served ONLY under
   `/v1/realtime/translations/*`. Driving it through the general `/v1/realtime` WS or
   `/v1/realtime/client_secrets` mint makes the backend route to a legacy
   `POST /v1/engines/gpt-realtime-translate/inference_stream` URL that 404s
   (`inference_not_found_error`). This — not account gating — was the whole blocker.

2. **The documented `audio.output.language` is valid only on the translations endpoint.**
   On `/v1/realtime` it returns `unknown_parameter` (REST mint and WS `session.update`,
   with or without `OpenAI-Beta` headers). On the translations endpoint it is the correct
   field.

3. **Verified mint (what the Worker does):**
   ```
   POST https://api.openai.com/v1/realtime/translations/client_secrets
   Authorization: Bearer $OPENAI_API_KEY
   { "session": { "model": "gpt-realtime-translate",
                  "audio": { "output": { "language": "<bcp47>" } } } }   # NO "type" field
   → 200 { "value": "ek_…", "expires_at": …, "session": { "type": "translation", … } }
   ```
   Client then exchanges SDP at `POST /v1/realtime/translations/calls` (Bearer `ek_`).

4. **WebSocket alternative** (server/Twilio-style):
   `wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate`,
   `session.`-prefixed client events (`session.update`, `session.input_audio_buffer.append`,
   `session.close`), **automatic** — append audio and it emits
   `session.output_transcript.delta` / `session.output_audio.delta`; there is no
   `response.create`, no commit. `session.update` takes only `{ audio: { output: { language } } }`
   (no `type`, no `audio.input.format`).

5. **No 13-language ceiling.** Feeding a real English clip and reading the output
   transcript, the model translated **faithfully** into all 21 languages tried:
   `es pt fr de it nl ru pl tr el ar he hi ja ko zh th vi id fi sv` — including the MENA /
   SE-Asia / Turkey / Greece / E-Europe corridors the design feared were blinded.
   `en→en` correctly emits **nothing** (the passthrough case). Cost is the flat $0.034/min.
   **→ The Azure fallback tier is retired from the plan.**

6. **`gpt-realtime-2` fallback.** The general flagship model also translates (via an
   "interpret only" `instructions` prompt over `/v1/realtime`), covers 70+ languages, but
   **occasionally drifts into answering** (e.g. Japanese came back as directions, not a
   translation) and is metered (~$32/1M audio-in, $64/1M audio-out → ~2–4× pricier). Kept
   as the emergency fallback only; the purpose-built translate model is primary.

## What changed in the code

> **Historical (2026-06-07).** These edits were made to the in-repo `workers/` worker, which has since been **removed** — the shipped backend is the shared **mako** service (repo `pixie`). The paths below no longer exist in this repo; they record what the spike changed at the time. `run.sh` is standalone and still re-runnable.

- `workers/src/lib/openai.ts` — mint + SDP URLs point at `/v1/realtime/translations/*`;
  mint body drops `type`.
- `workers/src/routes/session.ts` + `config.ts` — output-language gate + Azure 422 path
  removed (coverage is broad). `OPENAI_TRANSLATE_OUTPUT_LANGS` is now informational for
  `/v1/config` display, not a gate.

## Re-running

`run.sh` mints an ephemeral secret per candidate language at the **translations** endpoint
and reports acceptance (mint-only: no SDP, no audio). The key is read from
`$OPENAI_API_KEY` or `~/.openai-api-token` and is never printed or written.

```bash
OPENAI_API_KEY=sk-... ./run.sh
# or: printf '%s' 'sk-...' > ~/.openai-api-token && chmod 600 ~/.openai-api-token && ./run.sh
```

Full speech-translation behavior (audio in → translated transcript out) was verified with
a WebSocket audio probe against the translations endpoint; the coverage in finding 5 is its
result.
