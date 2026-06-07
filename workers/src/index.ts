import { Hono } from 'hono'
import type { AppVars, Env } from './env'
import { authRoutes } from './routes/auth'
import { configRoutes } from './routes/config'
import { sessionRoutes } from './routes/session'

const app = new Hono<{ Bindings: Env; Variables: AppVars }>()

app.get('/v1/healthz', (c) =>
  c.json({ ok: true, ts: new Date().toISOString(), env: c.env.ENVIRONMENT })
)

app.route('/', authRoutes)
app.route('/', configRoutes)
app.route('/', sessionRoutes)

app.onError((err, c) => {
  console.error(`unhandled ${c.req.method} ${c.req.path}:`, err)
  return c.json({ error: 'internal_error' }, 500)
})

app.notFound((c) => c.json({ error: 'not_found', path: c.req.path }, 404))

export default app
