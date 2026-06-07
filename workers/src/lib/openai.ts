import { sha256Hex } from './crypto'

export const OPENAI_CLIENT_SECRETS_URL =
  'https://api.openai.com/v1/realtime/translations/client_secrets'
export const OPENAI_SDP_URL = 'https://api.openai.com/v1/realtime/translations/calls'

export type MintedSecret = { ephemeralToken: string; expiresAt: Date }

export class OpenAIMintError extends Error {
  constructor(
    public readonly status: number,
    public readonly detail: string
  ) {
    super(`openai_mint_failed_${status}`)
  }
}

type ClientSecretResponse = {
  value?: string
  expires_at?: number
  ek?: string
  client_secret?: { value?: string; expires_at?: number }
}

/// Mints an ephemeral `ek_` client secret on the dedicated translations endpoint.
/// Verified live (Spike 1, 2026-06-07): gpt-realtime-translate is served only under
/// `/v1/realtime/translations/*` — the general `/v1/realtime` path 404s its inference.
/// POST translations/client_secrets with Bearer key + OpenAI-Safety-Identifier:
/// sha256(sub), body { session: { model, audio.output.language } } — NO `type`
/// field (the response sets session.type "translation"). Token is in `value` plus
/// expiry; the device then exchanges SDP at translations/calls.
export async function mintEphemeralSecret(args: {
  apiKey: string
  model: string
  outputLang: string
  sub: string
  expiresAfterSeconds?: number
  fetchImpl?: typeof fetch
}): Promise<MintedSecret> {
  const fetchImpl = args.fetchImpl ?? fetch
  const safetyIdentifier = await sha256Hex(args.sub)

  const res = await fetchImpl(OPENAI_CLIENT_SECRETS_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${args.apiKey}`,
      'Content-Type': 'application/json',
      'OpenAI-Safety-Identifier': safetyIdentifier,
    },
    body: JSON.stringify({
      expires_after: { anchor: 'created_at', seconds: args.expiresAfterSeconds ?? 120 },
      session: {
        model: args.model,
        audio: { output: { language: args.outputLang } },
      },
    }),
  })

  if (!res.ok) {
    const detail = await res.text().catch(() => '')
    throw new OpenAIMintError(res.status, detail.slice(0, 512))
  }

  const json = (await res.json()) as ClientSecretResponse
  const token = json.value ?? json.ek ?? json.client_secret?.value
  if (!token) throw new OpenAIMintError(502, 'missing_ephemeral_token')

  const expiresAtSec = json.expires_at ?? json.client_secret?.expires_at
  const expiresAt =
    typeof expiresAtSec === 'number'
      ? new Date(expiresAtSec * 1000)
      : new Date(Date.now() + (args.expiresAfterSeconds ?? 120) * 1000)

  return { ephemeralToken: token, expiresAt }
}
