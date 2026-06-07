import { beforeEach, describe, expect, it } from 'vitest'
import { guardAndReserveSession, releaseSession } from '../src/lib/sessions'
import { makeFakeKV } from './helpers/fakes'

describe('guardAndReserveSession', () => {
  let kv: KVNamespace

  beforeEach(() => {
    kv = makeFakeKV()
  })

  it('reserves up to the concurrency cap, then rejects', async () => {
    const a = await guardAndReserveSession(kv, 'u-1', 2, 6)
    const b = await guardAndReserveSession(kv, 'u-1', 2, 6)
    const c = await guardAndReserveSession(kv, 'u-1', 2, 6)
    expect(a.ok).toBe(true)
    expect(b.ok).toBe(true)
    expect(c.ok).toBe(false)
    if (!c.ok) expect(c.reason).toBe('concurrency')
  })

  it('frees a slot on release', async () => {
    const a = await guardAndReserveSession(kv, 'u-1', 1, 6)
    expect(a.ok).toBe(true)
    const blocked = await guardAndReserveSession(kv, 'u-1', 1, 6)
    expect(blocked.ok).toBe(false)
    if (a.ok) await releaseSession(kv, 'u-1', a.sessionId)
    const reopened = await guardAndReserveSession(kv, 'u-1', 1, 6)
    expect(reopened.ok).toBe(true)
  })

  it('enforces the per-minute mint cap independent of concurrency', async () => {
    const now = new Date('2026-06-06T12:00:00.000Z')
    let last
    for (let i = 0; i < 6; i++) {
      last = await guardAndReserveSession(kv, 'u-1', 100, 6, now)
      if (last.ok) await releaseSession(kv, 'u-1', last.sessionId)
    }
    const blocked = await guardAndReserveSession(kv, 'u-1', 100, 6, now)
    expect(blocked.ok).toBe(false)
    if (!blocked.ok) expect(blocked.reason).toBe('rate')
  })

  it('keeps separate buckets per user', async () => {
    await guardAndReserveSession(kv, 'u-1', 1, 6)
    const other = await guardAndReserveSession(kv, 'u-2', 1, 6)
    expect(other.ok).toBe(true)
  })
})
