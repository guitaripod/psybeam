import { Hono } from 'hono'
import type { AppVars, Env } from '../env'
import { requireAuth } from '../middleware/requireAuth'
import { debitQuota, reconcileQuota } from '../lib/quota'
import { guardAndReserveSession, releaseSession } from '../lib/sessions'
import { mintEphemeralSecret, OPENAI_SDP_URL, OpenAIMintError } from '../lib/openai'

const MAX_SESSION_SECONDS = 3600

type SessionBody = {
  targetLanguage?: string
  direction?: 'traveler' | 'local'
  estimatedMinutes?: number
}

export const sessionRoutes = new Hono<{ Bindings: Env; Variables: AppVars }>()

sessionRoutes.use('/v1/session', requireAuth)
sessionRoutes.use('/v1/session/usage', requireAuth)

sessionRoutes.post('/v1/session', async (c) => {
  const userId = c.get('userId')

  let body: SessionBody
  try {
    body = await c.req.json<SessionBody>()
  } catch {
    return c.json({ error: 'invalid_json' }, 400)
  }

  const targetLanguage = body.targetLanguage?.trim()
  if (!targetLanguage) return c.json({ error: 'targetLanguage_required' }, 400)

  const dailyMinutes = parseInt(c.env.FREE_DAILY_MINUTES, 10) || 0
  const requested = Math.max(1, Math.floor(body.estimatedMinutes ?? 1))

  const debit = await debitQuota(c.env.QUOTA, userId, requested, dailyMinutes)
  if (!debit.allowed) {
    return c.json({ error: 'quota_exhausted', minutesRemaining: debit.minutesRemaining }, 429)
  }

  const maxConcurrent = parseInt(c.env.MAX_CONCURRENT_SESSIONS, 10) || 2
  const maxMints = parseInt(c.env.MAX_MINTS_PER_MINUTE, 10) || 6
  const guard = await guardAndReserveSession(c.env.SESSIONS, userId, maxConcurrent, maxMints)
  if (!guard.ok) {
    return c.json(
      { error: guard.reason === 'rate' ? 'mint_rate_exceeded' : 'too_many_sessions' },
      429
    )
  }

  let minted
  try {
    minted = await mintEphemeralSecret({
      apiKey: c.env.OPENAI_API_KEY,
      model: c.env.OPENAI_TRANSLATE_MODEL || 'gpt-realtime-translate',
      outputLang: targetLanguage,
      sub: userId,
    })
  } catch (err) {
    await releaseSession(c.env.SESSIONS, userId, guard.sessionId)
    const status = err instanceof OpenAIMintError ? 502 : 500
    console.error('mint_upstream_failed:', (err as Error).message)
    return c.json({ error: 'mint_failed' }, status)
  }

  await c.env.DB.prepare(
    'INSERT INTO sessions (id, user_id, provider, target_lang, direction, minutes_reserved, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
  )
    .bind(
      guard.sessionId,
      userId,
      'openai',
      targetLanguage,
      body.direction ?? 'traveler',
      requested,
      new Date().toISOString()
    )
    .run()

  return c.json({
    provider: 'openai',
    ephemeralToken: minted.ephemeralToken,
    expiresAt: minted.expiresAt.toISOString(),
    sdpUrl: OPENAI_SDP_URL,
    model: c.env.OPENAI_TRANSLATE_MODEL || 'gpt-realtime-translate',
    targetLanguage,
    maxSessionSeconds: MAX_SESSION_SECONDS,
    sessionId: guard.sessionId,
    minutesRemaining: debit.minutesRemaining,
  })
})

sessionRoutes.post('/v1/session/usage', async (c) => {
  const userId = c.get('userId')

  let body: { sessionId?: string; minutesUsed?: number }
  try {
    body = await c.req.json()
  } catch {
    return c.json({ error: 'invalid_json' }, 400)
  }

  const dailyMinutes = parseInt(c.env.FREE_DAILY_MINUTES, 10) || 0
  const reported = Math.max(0, Math.floor(body.minutesUsed ?? 0))

  let reserved = 0
  if (body.sessionId) {
    const row = await c.env.DB.prepare(
      'SELECT minutes_reserved FROM sessions WHERE id = ? AND user_id = ?'
    )
      .bind(body.sessionId, userId)
      .first<{ minutes_reserved: number }>()
    reserved = row?.minutes_reserved ?? 0
    await releaseSession(c.env.SESSIONS, userId, body.sessionId)
    await c.env.DB.prepare(
      'UPDATE sessions SET minutes_used = ?, ended_at = ? WHERE id = ? AND user_id = ?'
    )
      .bind(reported, new Date().toISOString(), body.sessionId, userId)
      .run()
  }

  const { usedMinutes, minutesRemaining } = await reconcileQuota(
    c.env.QUOTA,
    userId,
    reserved,
    reported,
    dailyMinutes
  )

  return c.json({ usedMinutes, minutesRemaining })
})
