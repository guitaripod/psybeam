export type Env = {
  AUTH_NONCE: KVNamespace
  QUOTA: KVNamespace
  SESSIONS: KVNamespace
  DB: D1Database

  OPENAI_API_KEY: string
  APP_JWT_SECRET: string
  APPLE_CLIENT_ID: string
  APPLE_TEAM_ID: string

  OPENAI_TRANSLATE_OUTPUT_LANGS: string
  OPENAI_TRANSLATE_MODEL: string
  FREE_DAILY_MINUTES: string
  MAX_CONCURRENT_SESSIONS: string
  MAX_MINTS_PER_MINUTE: string
  ENVIRONMENT: string
}

export type AppVars = {
  userId: string
}
