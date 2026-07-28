import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'

const args = Object.fromEntries(process.argv.slice(2).map((a) => a.split('=')))
const TRANSCRIBE = args['--transcribe'] ?? 'none'
const OUT_LANG = args['--lang'] ?? 'es'
const PCM = args['--pcm'] ?? '/tmp/psybeam-spike6.pcm'
const SILENCE = Number(args['--silence'] ?? 8)
const WAIT = Number(args['--wait'] ?? 20)

const KEY = (process.env.OPENAI_API_KEY || readFileSync(`${homedir()}/.openai-api-token`, 'utf8')).trim()

const session = { model: 'gpt-realtime-translate', audio: { output: { language: OUT_LANG } } }
if (TRANSCRIBE !== 'none') session.audio.input = { transcription: { model: TRANSCRIBE } }

const mint = await fetch('https://api.openai.com/v1/realtime/translations/client_secrets', {
  method: 'POST',
  headers: { Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ session }),
})
const minted = await mint.json()
if (!mint.ok) {
  console.error(`mint rejected (${mint.status}): ${minted.error?.message ?? JSON.stringify(minted)}`)
  process.exit(1)
}
console.log(`mint ok    transcription=${TRANSCRIBE}  echo=${JSON.stringify(minted.session?.audio?.input ?? null)}`)

const ws = new WebSocket('wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate', [
  'realtime',
  `openai-insecure-api-key.${minted.value ?? minted.client_secret?.value}`,
])

const t0 = Date.now()
const at = () => String(Date.now() - t0).padStart(6)
const counts = new Map()
const first = new Map()
const last = new Map()
const gaps = new Map()
const text = new Map()
let reported = false

const report = (why) => {
  if (reported) return
  reported = true
  console.log(`\n  count   first   last  maxgap  event (${why})`)
  for (const [type, n] of [...counts.entries()].sort()) {
    const g = gaps.get(type) ?? []
    const maxGap = g.length ? Math.max(...g) : 0
    console.log(
      `  ${String(n).padStart(5)}  ${String(first.get(type)).padStart(6)}  ${String(last.get(type)).padStart(5)}  ${String(maxGap).padStart(6)}  ${type}`
    )
  }
  for (const [key, value] of text.entries()) console.log(`  ${key}: ${JSON.stringify(value)}`)
  const closing = [...counts.keys()].filter((t) => t.endsWith('.done') || t.endsWith('.completed'))
  console.log(`  CLOSING EVENTS: ${closing.length ? closing.join(', ') : 'NONE'}`)
  try { ws.close() } catch {}
  process.exit(0)
}

ws.onerror = (e) => { console.error('ws error', e.message ?? e); process.exit(1) }
ws.onclose = (e) => { console.log(`${at()} ws closed ${e.code} ${e.reason}`); report('closed') }

ws.onopen = async () => {
  const pcm = readFileSync(PCM)
  const CHUNK = 24000 * 2 * 0.1
  const send = (buf) =>
    ws.send(JSON.stringify({ type: 'session.input_audio_buffer.append', audio: buf.toString('base64') }))
  for (let i = 0; i < pcm.length; i += CHUNK) {
    send(pcm.subarray(i, Math.min(i + CHUNK, pcm.length)))
    await new Promise((r) => setTimeout(r, 100))
  }
  console.log(`${at()} sent ${(pcm.length / 48000).toFixed(2)}s speech, then ${SILENCE}s silence`)
  const quiet = Buffer.alloc(CHUNK)
  for (let i = 0; i < SILENCE * 10; i++) {
    send(quiet)
    await new Promise((r) => setTimeout(r, 100))
  }
  console.log(`${at()} idle, watching ${WAIT}s for a closing event`)
  setTimeout(() => report('timeout'), WAIT * 1000)
}

ws.onmessage = (m) => {
  let e
  try { e = JSON.parse(m.data) } catch { return }
  const now = Date.now() - t0
  counts.set(e.type, (counts.get(e.type) ?? 0) + 1)
  if (!first.has(e.type)) first.set(e.type, now)
  else {
    if (!gaps.has(e.type)) gaps.set(e.type, [])
    gaps.get(e.type).push(now - last.get(e.type))
  }
  last.set(e.type, now)
  if (e.type.includes('error')) console.log(`${at()} ${JSON.stringify(e).slice(0, 300)}`)
  const delta = e.delta ?? e.transcript
  if (typeof delta === 'string' && !e.type.includes('audio.delta')) {
    const key = e.type.replace(/\.(delta|done|completed)$/, '')
    text.set(key, (text.get(key) ?? '') + delta)
  }
}
