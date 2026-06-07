import * as jose from 'jose'
import { APPLE_CLIENT_ID } from './env'

export type AppleKey = {
  privateKey: CryptoKey
  publicKey: CryptoKey
  jwk: jose.JWK
  kid: string
}

export async function makeAppleKey(): Promise<AppleKey> {
  const { privateKey, publicKey } = await jose.generateKeyPair('RS256', { extractable: true })
  const jwk = await jose.exportJWK(publicKey)
  jwk.alg = 'RS256'
  jwk.use = 'sig'
  jwk.kid = 'unit-test-key'
  return { privateKey, publicKey, jwk, kid: jwk.kid }
}

export async function signAppleToken(
  key: AppleKey,
  overrides: Partial<{
    sub: string
    aud: string
    iss: string
    nonce: string
    email: string
    exp: number
  }> = {}
): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  return new jose.SignJWT({ nonce: overrides.nonce, email: overrides.email ?? 'tester@example.com' })
    .setProtectedHeader({ alg: 'RS256', kid: key.kid })
    .setIssuer(overrides.iss ?? 'https://appleid.apple.com')
    .setAudience(overrides.aud ?? APPLE_CLIENT_ID)
    .setSubject(overrides.sub ?? 'apple-sub-1')
    .setIssuedAt(now)
    .setExpirationTime(overrides.exp ?? now + 3600)
    .sign(key.privateKey)
}

export async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s))
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

export function mockAppleJWKS(jwk: jose.JWK): typeof globalThis.fetch {
  return (async (input: RequestInfo | URL) => {
    const url =
      typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url
    if (url === 'https://appleid.apple.com/auth/keys') {
      return new Response(JSON.stringify({ keys: [jwk] }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      })
    }
    throw new Error(`unexpected fetch in test: ${url}`)
  }) as typeof fetch
}
