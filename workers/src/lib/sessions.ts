import { utcMinuteStamp } from './crypto'

export type GuardResult =
  | { ok: true; sessionId: string }
  | { ok: false; reason: 'concurrency' | 'rate' }

const ACTIVE_TTL_SECONDS = 180
const MINT_RATE_TTL_SECONDS = 120

function activePrefix(userId: string): string {
  return `s:active:${userId}:`
}

function mintRateKey(userId: string, now: Date): string {
  return `s:mint:${userId}:${utcMinuteStamp(now)}`
}

async function countActive(kv: KVNamespace, userId: string): Promise<number> {
  let cursor: string | undefined
  let total = 0
  do {
    const page = await kv.list({ prefix: activePrefix(userId), cursor })
    total += page.keys.length
    cursor = page.list_complete ? undefined : page.cursor
  } while (cursor)
  return total
}

/// Enforces <=maxConcurrent live sessions and <=maxMintsPerMinute per user, then
/// reserves a fresh sessionId. Each active session is one KV key under
/// `s:active:<uid>:` carrying a SHORT TTL so reservations leaked by an abrupt
/// teardown (force-quit, crash, redeploy) self-evict quickly; the client also
/// releases explicitly on hang-up/background. Production should heartbeat-refresh
/// the key for sessions that legitimately outlive the TTL.
export async function guardAndReserveSession(
  kv: KVNamespace,
  userId: string,
  maxConcurrent: number,
  maxMintsPerMinute: number,
  now: Date = new Date()
): Promise<GuardResult> {
  const rateKey = mintRateKey(userId, now)
  const mints = parseInt((await kv.get(rateKey)) ?? '0', 10) || 0
  if (mints >= maxMintsPerMinute) {
    return { ok: false, reason: 'rate' }
  }

  const active = await countActive(kv, userId)
  if (active >= maxConcurrent) {
    return { ok: false, reason: 'concurrency' }
  }

  await kv.put(rateKey, String(mints + 1), { expirationTtl: MINT_RATE_TTL_SECONDS })

  const sessionId = crypto.randomUUID()
  await kv.put(`${activePrefix(userId)}${sessionId}`, String(now.getTime()), {
    expirationTtl: ACTIVE_TTL_SECONDS,
  })
  return { ok: true, sessionId }
}

export async function releaseSession(
  kv: KVNamespace,
  userId: string,
  sessionId: string
): Promise<void> {
  await kv.delete(`${activePrefix(userId)}${sessionId}`)
}
