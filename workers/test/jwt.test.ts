import { describe, expect, it } from 'vitest'
import * as jose from 'jose'
import { mintAppJWT, verifyAppJWT } from '../src/lib/jwt'

const SECRET = 'test-secret-do-not-use-in-prod'

describe('mintAppJWT / verifyAppJWT', () => {
  it('round-trips claims', async () => {
    const token = await mintAppJWT({ uid: 'u-1', email: 'a@b.com', name: 'Marcus' }, SECRET)
    const claims = await verifyAppJWT(token, SECRET)
    expect(claims.uid).toBe('u-1')
    expect(claims.email).toBe('a@b.com')
    expect(claims.name).toBe('Marcus')
  })

  it('rejects a token signed with a different secret', async () => {
    const token = await mintAppJWT({ uid: 'u-1' }, SECRET)
    await expect(verifyAppJWT(token, 'other-secret')).rejects.toThrow()
  })

  it('rejects a token with the wrong issuer', async () => {
    const token = await new jose.SignJWT({ uid: 'u-1' })
      .setProtectedHeader({ alg: 'HS256' })
      .setIssuer('not-psybeam')
      .setAudience('psybeam-ios')
      .setExpirationTime('1h')
      .sign(new TextEncoder().encode(SECRET))
    await expect(verifyAppJWT(token, SECRET)).rejects.toThrow()
  })

  it('rejects an expired token', async () => {
    const token = await new jose.SignJWT({ uid: 'u-1' })
      .setProtectedHeader({ alg: 'HS256' })
      .setIssuer('psybeam')
      .setAudience('psybeam-ios')
      .setIssuedAt(Math.floor(Date.now() / 1000) - 7200)
      .setExpirationTime(Math.floor(Date.now() / 1000) - 3600)
      .sign(new TextEncoder().encode(SECRET))
    await expect(verifyAppJWT(token, SECRET)).rejects.toThrow()
  })

  it('rejects a token with no uid claim', async () => {
    const token = await new jose.SignJWT({})
      .setProtectedHeader({ alg: 'HS256' })
      .setIssuer('psybeam')
      .setAudience('psybeam-ios')
      .setExpirationTime('1h')
      .sign(new TextEncoder().encode(SECRET))
    await expect(verifyAppJWT(token, SECRET)).rejects.toThrow(/uid/)
  })
})
