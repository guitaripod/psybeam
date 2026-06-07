import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import app from '../src/index'
import { makeEnv } from './helpers/env'
import { makeAppleKey, mockAppleJWKS, sha256Hex, signAppleToken, type AppleKey } from './helpers/apple'

let appleKey: AppleKey
let originalFetch: typeof globalThis.fetch

beforeAll(async () => {
  appleKey = await makeAppleKey()
})

beforeEach(() => {
  originalFetch = globalThis.fetch
  globalThis.fetch = vi.fn(mockAppleJWKS(appleKey.jwk))
})

afterEach(() => {
  globalThis.fetch = originalFetch
})

describe('POST /v1/auth/apple', () => {
  it('verifies a synthetic Apple token, creates a user, and mints an app JWT', async () => {
    const nonce = 'raw-nonce-abc'
    const idToken = await signAppleToken(appleKey, { nonce: await sha256Hex(nonce) })

    const res = await app.request(
      '/v1/auth/apple',
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          identityToken: idToken,
          rawNonce: nonce,
          fullName: { givenName: 'Marcus', familyName: 'Test' },
        }),
      },
      makeEnv()
    )

    expect(res.status).toBe(200)
    const json = (await res.json()) as { token: string; user: { email: string; name: string } }
    expect(json.token).toMatch(/^eyJ/)
    expect(json.user.name).toBe('Marcus Test')
  })

  it('rejects a replayed nonce', async () => {
    const env = makeEnv()
    const nonce = 'replay-me'
    const hashed = await sha256Hex(nonce)

    const first = await app.request(
      '/v1/auth/apple',
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          identityToken: await signAppleToken(appleKey, { nonce: hashed }),
          rawNonce: nonce,
        }),
      },
      env
    )
    expect(first.status).toBe(200)

    const second = await app.request(
      '/v1/auth/apple',
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          identityToken: await signAppleToken(appleKey, { nonce: hashed }),
          rawNonce: nonce,
        }),
      },
      env
    )
    expect(second.status).toBe(401)
    expect(((await second.json()) as { error: string }).error).toBe('nonce_replayed')
  })

  it('rejects a mismatched audience', async () => {
    const idToken = await signAppleToken(appleKey, { aud: 'com.someone.else' })
    const res = await app.request(
      '/v1/auth/apple',
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ identityToken: idToken }),
      },
      makeEnv()
    )
    expect(res.status).toBe(401)
  })

  it('rejects a mismatched nonce', async () => {
    const idToken = await signAppleToken(appleKey, { nonce: await sha256Hex('a-nonce') })
    const res = await app.request(
      '/v1/auth/apple',
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ identityToken: idToken, rawNonce: 'different-nonce' }),
      },
      makeEnv()
    )
    expect(res.status).toBe(401)
    expect(((await res.json()) as { error: string }).error).toBe('nonce_mismatch')
  })

  it('400s on a missing identityToken', async () => {
    const res = await app.request(
      '/v1/auth/apple',
      { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' },
      makeEnv()
    )
    expect(res.status).toBe(400)
  })
})

describe('POST /v1/auth/refresh', () => {
  it('rotates a valid app JWT', async () => {
    const env = makeEnv()
    const signIn = await app.request(
      '/v1/auth/apple',
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          identityToken: await signAppleToken(appleKey, { sub: 'refresh-sub' }),
          fullName: { givenName: 'Ada' },
        }),
      },
      env
    )
    const { token } = (await signIn.json()) as { token: string }

    const res = await app.request(
      '/v1/auth/refresh',
      { method: 'POST', headers: { Authorization: `Bearer ${token}` } },
      env
    )
    expect(res.status).toBe(200)
    const json = (await res.json()) as { token: string; user: { name: string } }
    expect(json.token).toMatch(/^eyJ/)
    expect(json.user.name).toBe('Ada')
  })

  it('401s without a bearer header', async () => {
    const res = await app.request('/v1/auth/refresh', { method: 'POST' }, makeEnv())
    expect(res.status).toBe(401)
  })
})
