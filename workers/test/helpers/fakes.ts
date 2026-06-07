export function makeFakeKV(): KVNamespace {
  const store = new Map<string, string>()
  return {
    get: async (key: string) => store.get(key) ?? null,
    put: async (key: string, value: string) => {
      store.set(key, value)
    },
    delete: async (key: string) => {
      store.delete(key)
    },
    list: async (opts?: { prefix?: string; cursor?: string }) => {
      const prefix = opts?.prefix ?? ''
      const keys = Array.from(store.keys())
        .filter((k) => k.startsWith(prefix))
        .map((name) => ({ name }))
      return { keys, list_complete: true, cacheStatus: null }
    },
    getWithMetadata: async () => ({ value: null, metadata: null, cacheStatus: null }),
  } as unknown as KVNamespace
}

type Row = Record<string, unknown>

export function makeFakeD1(): D1Database {
  const users = new Map<string, Row>()
  const sessions = new Map<string, Row>()

  const exec = (sql: string, params: unknown[]): Row[] => {
    const s = sql.replace(/\s+/g, ' ').trim()

    if (/^SELECT id, email, name FROM users WHERE apple_sub = \?/.test(s)) {
      for (const u of users.values()) if (u.apple_sub === params[0]) return [u]
      return []
    }
    if (/^SELECT id, email, name FROM users WHERE id = \?/.test(s)) {
      const u = users.get(params[0] as string)
      return u ? [u] : []
    }
    if (/^INSERT INTO users/.test(s)) {
      const [id, apple_sub, email, name] = params as [string, string, string | null, string | null]
      users.set(id, { id, apple_sub, email, name })
      return []
    }
    if (/^UPDATE users SET email = \?, name = \? WHERE id = \?/.test(s)) {
      const [email, name, id] = params as [string | null, string | null, string]
      const u = users.get(id)
      if (u) {
        u.email = email
        u.name = name
      }
      return []
    }
    if (/^SELECT minutes_reserved FROM sessions WHERE id = \? AND user_id = \?/.test(s)) {
      const row = sessions.get(params[0] as string)
      if (!row) return []
      return [{ minutes_reserved: (row.params as unknown[])[5] }]
    }
    if (/^INSERT INTO sessions/.test(s)) {
      const id = params[0] as string
      sessions.set(id, { id, params })
      return []
    }
    if (/^UPDATE sessions/.test(s)) {
      return []
    }
    if (/^INSERT INTO usage_ledger/.test(s)) {
      return []
    }
    throw new Error(`fake D1 saw unexpected SQL: ${s}`)
  }

  const prepare = (sql: string) => {
    let bound: unknown[] = []
    const stmt = {
      bind(...args: unknown[]) {
        bound = args
        return stmt
      },
      async first<T>() {
        const rows = exec(sql, bound) as T[]
        return rows[0] ?? null
      },
      async run() {
        exec(sql, bound)
        return { success: true, meta: {} } as unknown as D1Result
      },
      async all<T>() {
        return { results: exec(sql, bound) as T[], success: true, meta: {} } as unknown as D1Result<T>
      },
    }
    return stmt as unknown as D1PreparedStatement
  }

  return {
    prepare,
    _users: users,
    _sessions: sessions,
  } as unknown as D1Database & { _users: Map<string, Row>; _sessions: Map<string, Row> }
}

export type FakeD1 = ReturnType<typeof makeFakeD1> & {
  _users: Map<string, Row>
  _sessions: Map<string, Row>
}
