import { beforeEach, describe, expect, it } from 'vitest'
import { debitQuota, peekQuota, reconcileQuota } from '../src/lib/quota'
import { makeFakeKV } from './helpers/fakes'

describe('debitQuota', () => {
  let kv: KVNamespace

  beforeEach(() => {
    kv = makeFakeKV()
  })

  it('debits and reports remaining', async () => {
    const r = await debitQuota(kv, 'u-1', 3, 10)
    expect(r.allowed).toBe(true)
    expect(r.usedMinutes).toBe(3)
    expect(r.minutesRemaining).toBe(7)
  })

  it('accumulates across debits', async () => {
    await debitQuota(kv, 'u-1', 4, 10)
    const r = await debitQuota(kv, 'u-1', 5, 10)
    expect(r.usedMinutes).toBe(9)
    expect(r.minutesRemaining).toBe(1)
  })

  it('rejects when the debit would exceed the daily allowance and does not write', async () => {
    await debitQuota(kv, 'u-1', 10, 10)
    const blocked = await debitQuota(kv, 'u-1', 1, 10)
    expect(blocked.allowed).toBe(false)
    expect(blocked.minutesRemaining).toBe(0)
    const peek = await peekQuota(kv, 'u-1', 10)
    expect(peek.usedMinutes).toBe(10)
  })

  it('rejects at exactly zero remaining', async () => {
    const exhausted = makeFakeKV()
    await debitQuota(exhausted, 'u-2', 10, 10)
    const r = await debitQuota(exhausted, 'u-2', 1, 10)
    expect(r.allowed).toBe(false)
    expect(r.minutesRemaining).toBe(0)
  })

  it('keeps separate buckets per user', async () => {
    await debitQuota(kv, 'u-1', 8, 10)
    const other = await peekQuota(kv, 'u-2', 10)
    expect(other.minutesRemaining).toBe(10)
  })
})

describe('reconcileQuota', () => {
  it('swaps the mint reservation for actual minutes used', async () => {
    const kv = makeFakeKV()
    await debitQuota(kv, 'u-1', 1, 240)
    const r = await reconcileQuota(kv, 'u-1', 1, 4, 240)
    expect(r.usedMinutes).toBe(4)
    expect(r.minutesRemaining).toBe(236)
  })

  it('refunds the reservation when a connect never really used time', async () => {
    const kv = makeFakeKV()
    await debitQuota(kv, 'u-1', 1, 240)
    const r = await reconcileQuota(kv, 'u-1', 1, 0, 240)
    expect(r.usedMinutes).toBe(0)
    expect(r.minutesRemaining).toBe(240)
  })

  it('clamps a spoofed over-report to the daily ceiling', async () => {
    const kv = makeFakeKV()
    await debitQuota(kv, 'u-1', 1, 10)
    const r = await reconcileQuota(kv, 'u-1', 1, 9999, 10)
    expect(r.usedMinutes).toBe(10)
    expect(r.minutesRemaining).toBe(0)
  })
})
