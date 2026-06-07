import { Hono } from 'hono'
import type { AppVars, Env } from '../env'
import { requireAuth } from '../middleware/requireAuth'
import { parseOutputLangs } from '../lib/langs'
import { peekQuota } from '../lib/quota'

export const configRoutes = new Hono<{ Bindings: Env; Variables: AppVars }>()

configRoutes.use('/v1/config', requireAuth)
configRoutes.use('/v1/me/quota', requireAuth)

configRoutes.get('/v1/config', async (c) => {
  const userId = c.get('userId')
  const localLanguage = c.req.query('localLanguage') ?? null

  const supported = parseOutputLangs(c.env.OPENAI_TRANSLATE_OUTPUT_LANGS)
  const translateSupported = true
  const recommendedPath = 'openai'

  const dailyMinutes = parseInt(c.env.FREE_DAILY_MINUTES, 10) || 0
  const { minutesRemaining } = await peekQuota(c.env.QUOTA, userId, dailyMinutes)

  return c.json({
    localLanguage,
    translateSupported,
    recommendedPath,
    supportedOutputLangs: supported,
    minutesRemaining,
  })
})

configRoutes.get('/v1/me/quota', async (c) => {
  const userId = c.get('userId')
  const dailyMinutes = parseInt(c.env.FREE_DAILY_MINUTES, 10) || 0
  const { usedMinutes, minutesRemaining } = await peekQuota(c.env.QUOTA, userId, dailyMinutes)
  return c.json({ dailyMinutes, usedMinutes, minutesRemaining })
})
