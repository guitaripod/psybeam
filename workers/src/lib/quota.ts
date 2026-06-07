import { utcDayStamp } from './crypto'

export type QuotaState = { usedMinutes: number; minutesRemaining: number; allowed: boolean }

const DAY_TTL_SECONDS = 60 * 60 * 26

function quotaKey(userId: string, now: Date): string {
  return `q:${userId}:${utcDayStamp(now)}`
}

async function readUsed(kv: KVNamespace, key: string): Promise<number> {
  const raw = await kv.get(key)
  const n = raw == null ? 0 : parseInt(raw, 10)
  return Number.isFinite(n) && n >= 0 ? n : 0
}

export async function peekQuota(
  kv: KVNamespace,
  userId: string,
  dailyMinutes: number,
  now: Date = new Date()
): Promise<{ usedMinutes: number; minutesRemaining: number }> {
  const used = await readUsed(kv, quotaKey(userId, now))
  return { usedMinutes: used, minutesRemaining: Math.max(0, dailyMinutes - used) }
}

/// Atomic-as-KV-allows debit BEFORE a token is minted. Read-modify-write: read the
/// day counter, reject when the requested minutes would exceed the daily allowance,
/// otherwise write the incremented value with a 26h TTL. This is the central
/// anti-abuse fix — a leaked app JWT is bounded to `dailyMinutes` per user/day
/// instead of unbounded mints. The residual KV read-modify-write race is documented
/// in the README; the OpenAI 60-min hard cap bounds any single connected session.
export async function debitQuota(
  kv: KVNamespace,
  userId: string,
  minutes: number,
  dailyMinutes: number,
  now: Date = new Date()
): Promise<QuotaState> {
  const key = quotaKey(userId, now)
  const used = await readUsed(kv, key)
  if (used + minutes > dailyMinutes) {
    return { usedMinutes: used, minutesRemaining: Math.max(0, dailyMinutes - used), allowed: false }
  }
  const next = used + minutes
  await kv.put(key, String(next), { expirationTtl: DAY_TTL_SECONDS })
  return { usedMinutes: next, minutesRemaining: Math.max(0, dailyMinutes - next), allowed: true }
}

/// Reconciles a finished session: swap its mint-time reservation for the actual
/// minutes the client reports. `next = used - reserved + actual` — so a session
/// that never really connected (actual 0) refunds its reservation, and a long
/// session charges what it used. Clamped to [0, dailyMinutes].
export async function reconcileQuota(
  kv: KVNamespace,
  userId: string,
  reservedMinutes: number,
  actualMinutes: number,
  dailyMinutes: number,
  now: Date = new Date()
): Promise<{ usedMinutes: number; minutesRemaining: number }> {
  const key = quotaKey(userId, now)
  const used = await readUsed(kv, key)
  const reserved = Math.max(0, Math.floor(reservedMinutes))
  const actual = Math.max(0, Math.min(Math.floor(actualMinutes), dailyMinutes))
  const next = Math.max(0, used - reserved + actual)
  await kv.put(key, String(next), { expirationTtl: DAY_TTL_SECONDS })
  return { usedMinutes: next, minutesRemaining: Math.max(0, dailyMinutes - next) }
}
