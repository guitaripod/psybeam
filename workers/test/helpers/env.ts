import type { Env } from '../../src/env'
import { makeFakeD1, makeFakeKV } from './fakes'

export const APPLE_CLIENT_ID = 'com.guitaripod.psybeam'
export const APPLE_TEAM_ID = 'AAAA111111'
export const APP_JWT_SECRET = 'unit-test-secret-do-not-use'
export const OUTPUT_LANGS = 'es,pt,fr,ja,ru,zh,de,ko,hi,id,vi,it,en'

export type TestEnv = Env & {
  AUTH_NONCE: KVNamespace
  QUOTA: KVNamespace
  SESSIONS: KVNamespace
  DB: D1Database
}

export function makeEnv(overrides: Partial<Env> = {}): TestEnv {
  return {
    AUTH_NONCE: makeFakeKV(),
    QUOTA: makeFakeKV(),
    SESSIONS: makeFakeKV(),
    DB: makeFakeD1(),
    OPENAI_API_KEY: 'sk-fake-openai-key',
    APP_JWT_SECRET,
    APPLE_CLIENT_ID,
    APPLE_TEAM_ID,
    OPENAI_TRANSLATE_OUTPUT_LANGS: OUTPUT_LANGS,
    OPENAI_TRANSLATE_MODEL: 'gpt-realtime-translate',
    FREE_DAILY_MINUTES: '10',
    MAX_CONCURRENT_SESSIONS: '2',
    MAX_MINTS_PER_MINUTE: '6',
    ENVIRONMENT: 'test',
    ...overrides,
  } as TestEnv
}
