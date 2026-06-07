# psybeam-worker

Cloudflare Worker (Hono v4 + jose v6) that brokers ephemeral OpenAI Realtime
tokens for [Psybeam](../DESIGN.md). The real `OPENAI_API_KEY` never leaves
Cloudflare; the iPhone connects to OpenAI directly over WebRTC using a short-lived
`ek_` minted here. Sign in with Apple gates everything; an HS256 app JWT authorizes
every non-auth route.

See [`../DESIGN.md`](../DESIGN.md) §5 for the full surface and the corrected abuse
model. This README covers running, secrets, and the load-bearing implementation
notes.

## Routes

| Method + Path | Auth | Purpose |
|---|---|---|
| `GET /v1/healthz` | — | Liveness. |
| `POST /v1/auth/apple` | — | Verify Apple `id_token` via Apple JWKS (jose), nonce replay-guard in `AUTH_NONCE` (5m TTL), upsert user in D1, mint HS256 app JWT. |
| `POST /v1/auth/refresh` | app JWT | Rotate the app JWT (hourly). |
| `GET /v1/config` | app JWT | `ConfigResponse` — informational language list + minutes remaining. |
| `POST /v1/session` | app JWT | **The broker.** Atomic quota debit → concurrency/rate guard → upstream `ek_` mint → `SessionToken`. |
| `POST /v1/session/usage` | app JWT | Advisory reconcile of client-reported minutes; releases the session slot. |
| `GET /v1/me/quota` | app JWT | Daily allowance, used, remaining. |

Every route except `/v1/auth/*` (and `/v1/healthz`) runs the `requireAuth`
middleware, which verifies the app JWT and sets `userId` on the context.

## The broker — `POST /v1/session`

Request: `{ targetLanguage: string /* BCP-47 */, direction?: "traveler" | "local", estimatedMinutes?: number }`.

1. **Verify app JWT → `userId`** (middleware).
2. **Atomic quota debit at mint time.** `QUOTA` key `q:<userId>:<YYYYMMDD>` is
   read-modify-written **before** the token is minted. Insufficient → **429
   `quota_exhausted`**. This is the central anti-abuse fix (see below).
3. **Concurrency + mint-rate guard.** `SESSIONS` enforces `≤ MAX_CONCURRENT_SESSIONS`
   (default 2) live sessions and `≤ MAX_MINTS_PER_MINUTE` (default 6) mints/min per
   user. Over cap → **429** (`too_many_sessions` / `mint_rate_exceeded`).
4. **Mint upstream** with the real key, on the dedicated translations endpoint:
   `POST https://api.openai.com/v1/realtime/translations/client_secrets`,
   `Authorization: Bearer OPENAI_API_KEY`, `Content-Type: application/json`,
   `OpenAI-Safety-Identifier: sha256(userId)`,
   body `{ expires_after, session: { model:"gpt-realtime-translate", audio:{ output:{ language:<target> } } } }` — **no `type`** (the response sets `session.type:"translation"`). The token is in `value`. There is **no output-language gate**: Spike 1 verified the model speaks 20+ languages, so any requested target is minted. On upstream failure the reserved session slot is released and the request returns 502.
5. **Return** a `SessionToken` with the **exact contract field names**:
   `{ provider, ephemeralToken, expiresAt, sdpUrl:"https://api.openai.com/v1/realtime/translations/calls", model, targetLanguage, maxSessionSeconds:3600, sessionId, minutesRemaining }`.
   The iPhone does the SDP exchange against `sdpUrl` directly.

### The atomic-debit-at-mint fix, and its residual race

The real attack surface is a **leaked app JWT minting unbounded sessions**, not one
leaked `ek_` (a single connected session is bounded by OpenAI's hard **60-minute**
cap). Debiting the daily quota **before** the token is minted bounds a leaked JWT to
`FREE_DAILY_MINUTES` per user/day; client-reported `/v1/session/usage` is advisory
reconciliation only (trivially spoofable, so it can only ratchet usage **upward**
and is clamped to the daily ceiling).

**Residual race (documented, accepted for MVP):** Workers KV is eventually
consistent and has no compare-and-swap, so the debit is a best-effort
read-modify-write. Two mints racing on the same key within the replication window
can both read the same pre-decrement value and over-spend by up to
`(concurrent_racers − 1) × estimatedMinutes`. This is bounded in practice by:
(a) the `MAX_CONCURRENT_SESSIONS` cap (default 2) and the per-minute mint cap,
(b) OpenAI's 60-min hard per-session cap, and (c) the D1 `usage_ledger` /
`sessions` rows as the durable reconciliation source. If the free tier ever needs
hard correctness, move the counter to a Durable Object (single-threaded
compare-and-swap) — intentionally **not** done for MVP per DESIGN (no DO binding).

## The output-language list (informational)

`OPENAI_TRANSLATE_OUTPUT_LANGS` is a **`var`**, not hardcoded in any binary, and is
**informational only** — it populates `GET /v1/config`'s `supportedOutputLangs` for
display and does **not** gate minting. Spike 1 (2026-06-07) verified
`gpt-realtime-translate` translates 20+ languages, so any requested target is minted. A
change is a Worker deploy (`wrangler deploy`), never an App Store submission. The iOS
client reads the live list from `GET /v1/config` and must never embed its own copy.

## Bindings

| Binding | Type | Purpose |
|---|---|---|
| `AUTH_NONCE` | KV | Apple `id_token` nonce replay guard (5m TTL). |
| `QUOTA` | KV | Per-user atomic daily minute ledger (`q:<uid>:<YYYYMMDD>`). |
| `SESSIONS` | KV | Concurrency (`s:active:<uid>:<sid>`) + mint-rate (`s:mint:<uid>:<minute>`). |
| `DB` | D1 | Durable `users` / `sessions` / `usage_ledger` (see `schema.sql`). |

> **TODO:** `wrangler.jsonc` ships with **placeholder** KV/D1 ids. Create the real
> resources and paste the ids before deploying:
>
> ```bash
> npx wrangler kv namespace create AUTH_NONCE
> npx wrangler kv namespace create QUOTA
> npx wrangler kv namespace create SESSIONS
> npx wrangler d1 create psybeam
> npx wrangler d1 execute psybeam --file=./schema.sql      # local: add --local
> ```

## Secrets

Set in **both** production (`wrangler secret put`) and locally (`.dev.vars`, copy
from `.dev.vars.example`). The two stores are independent. Never commit `.dev.vars`.

| Secret | Used for |
|---|---|
| `OPENAI_API_KEY` | Upstream `ek_` mint (the key that never leaves Cloudflare). |
| `APP_JWT_SECRET` | HS256 sign/verify of the app JWT. Use a long random string. |
| `APPLE_CLIENT_ID` | Apple `id_token` audience (the app's Service/bundle id, e.g. `com.guitaripod.psybeam`). |
| `APPLE_TEAM_ID` | Apple developer team id. |

```bash
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put APP_JWT_SECRET
npx wrangler secret put APPLE_CLIENT_ID
npx wrangler secret put APPLE_TEAM_ID
```

## Develop, test, deploy

```bash
npm install
npm run typecheck     # tsc --noEmit (src)
npm test              # vitest run (OpenAI fetch mocked; no network)
npx wrangler dev      # local, reads .dev.vars
npx wrangler deploy   # production (set real ids + secrets first)
```

Tests run in the node environment with in-memory KV/D1 fakes and a mocked OpenAI
`client_secrets` fetch — no network, no Miniflare boot. `@cloudflare/vitest-pool-workers`
is included as a devDep for anyone who later wants Miniflare-backed integration tests.
