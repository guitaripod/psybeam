import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import app from '../src/index'
import { mintAppJWT } from '../src/lib/jwt'
import { debitQuota } from '../src/lib/quota'
import { OPENAI_CLIENT_SECRETS_URL, OPENAI_SDP_URL } from '../src/lib/openai'
import { APP_JWT_SECRET, makeEnv, type TestEnv } from './helpers/env'

let originalFetch: typeof globalThis.fetch
let mintCalls: { headers: Headers; body: unknown }[]

function mockOpenAI(): typeof globalThis.fetch {
  return (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url =
      typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url
    if (url === OPENAI_CLIENT_SECRETS_URL) {
      mintCalls.push({
        headers: new Headers(init?.headers),
        body: init?.body ? JSON.parse(init.body as string) : undefined,
      })
      return new Response(
        JSON.stringify({ value: 'ek_test_token', expires_at: Math.floor(Date.now() / 1000) + 120 }),
        { status: 200, headers: { 'content-type': 'application/json' } }
      )
    }
    throw new Error(`unexpected fetch in test: ${url}`)
  }) as typeof fetch
}

async function bearer(uid = 'user-1'): Promise<string> {
  return mintAppJWT({ uid }, APP_JWT_SECRET)
}

function post(path: string, token: string, body: unknown, env: TestEnv) {
  return app.request(
    path,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify(body),
    },
    env
  )
}

beforeEach(() => {
  originalFetch = globalThis.fetch
  mintCalls = []
  globalThis.fetch = vi.fn(mockOpenAI())
})

afterEach(() => {
  globalThis.fetch = originalFetch
})

describe('POST /v1/session', () => {
  it('401s without a bearer token', async () => {
    const res = await app.request(
      '/v1/session',
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ targetLanguage: 'es' }),
      },
      makeEnv()
    )
    expect(res.status).toBe(401)
  })

  it('mints a SessionToken with the exact contract field names for a supported lang (es)', async () => {
    const env = makeEnv()
    const token = await bearer()
    const res = await post('/v1/session', token, { targetLanguage: 'es', estimatedMinutes: 1 }, env)

    expect(res.status).toBe(200)
    const json = (await res.json()) as Record<string, unknown>
    expect(json.provider).toBe('openai')
    expect(json.ephemeralToken).toBe('ek_test_token')
    expect(typeof json.expiresAt).toBe('string')
    expect(json.sdpUrl).toBe(OPENAI_SDP_URL)
    expect(json.model).toBe('gpt-realtime-translate')
    expect(json.targetLanguage).toBe('es')
    expect(json.maxSessionSeconds).toBe(3600)
    expect(typeof json.sessionId).toBe('string')
    expect(json.minutesRemaining).toBe(9)
  })

  it('sends the confirmed upstream mint shape + Safety-Identifier header', async () => {
    const env = makeEnv()
    const token = await bearer()
    await post('/v1/session', token, { targetLanguage: 'es' }, env)

    expect(mintCalls).toHaveLength(1)
    const call = mintCalls[0]!
    expect(call.headers.get('Authorization')).toBe('Bearer sk-fake-openai-key')
    expect(call.headers.get('OpenAI-Safety-Identifier')).toMatch(/^[0-9a-f]{64}$/)
    const body = call.body as { session: { model: string; audio: { output: { language: string } } } }
    expect(body.session.model).toBe('gpt-realtime-translate')
    expect(body.session.audio.output.language).toBe('es')
  })

  it('mints for a broad-coverage language (ar) — no 13-language gate', async () => {
    const env = makeEnv()
    const token = await bearer()
    const res = await post('/v1/session', token, { targetLanguage: 'ar' }, env)

    expect(res.status).toBe(200)
    const json = (await res.json()) as { provider: string; targetLanguage: string }
    expect(json.provider).toBe('openai')
    expect(json.targetLanguage).toBe('ar')
    expect(mintCalls).toHaveLength(1)
    const body = mintCalls[0]!.body as { session: { audio: { output: { language: string } } } }
    expect(body.session.audio.output.language).toBe('ar')
  })

  it('429s when the daily quota is exhausted, and does not call OpenAI', async () => {
    const env = makeEnv()
    await debitQuota(env.QUOTA, 'user-1', 10, 10)
    const token = await bearer('user-1')
    const res = await post('/v1/session', token, { targetLanguage: 'es' }, env)

    expect(res.status).toBe(429)
    expect(((await res.json()) as { error: string }).error).toBe('quota_exhausted')
    expect(mintCalls).toHaveLength(0)
  })

  it('429s when the concurrency cap is hit', async () => {
    const env = makeEnv()
    const token = await bearer('busy-user')
    const a = await post('/v1/session', token, { targetLanguage: 'es' }, env)
    const b = await post('/v1/session', token, { targetLanguage: 'es' }, env)
    const c = await post('/v1/session', token, { targetLanguage: 'es' }, env)

    expect(a.status).toBe(200)
    expect(b.status).toBe(200)
    expect(c.status).toBe(429)
    expect(((await c.json()) as { error: string }).error).toBe('too_many_sessions')
  })
})

describe('POST /v1/session/usage', () => {
  it('reconciles reported minutes and releases the session', async () => {
    const env = makeEnv()
    const token = await bearer('recon-user')
    const minted = await post('/v1/session', token, { targetLanguage: 'es' }, env)
    const { sessionId } = (await minted.json()) as { sessionId: string }

    const res = await post('/v1/session/usage', token, { sessionId, minutesUsed: 4 }, env)
    expect(res.status).toBe(200)
    const json = (await res.json()) as { usedMinutes: number; minutesRemaining: number }
    expect(json.usedMinutes).toBe(4)
    expect(json.minutesRemaining).toBe(6)
  })
})

describe('GET /v1/config + /v1/me/quota', () => {
  it('reports the supported langs and remaining minutes', async () => {
    const env = makeEnv()
    const token = await bearer('cfg-user')
    const res = await app.request(
      '/v1/config?localLanguage=th',
      { headers: { Authorization: `Bearer ${token}` } },
      env
    )
    expect(res.status).toBe(200)
    const json = (await res.json()) as {
      translateSupported: boolean
      recommendedPath: string
      supportedOutputLangs: string[]
      minutesRemaining: number
    }
    expect(json.translateSupported).toBe(true)
    expect(json.recommendedPath).toBe('openai')
    expect(json.supportedOutputLangs).toContain('es')
    expect(json.minutesRemaining).toBe(10)
  })

  it('401s /v1/me/quota without auth', async () => {
    const res = await app.request('/v1/me/quota', {}, makeEnv())
    expect(res.status).toBe(401)
  })
})
