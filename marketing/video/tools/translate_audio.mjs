#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { homedir } from 'node:os'
import { execFileSync } from 'node:child_process'

const SAMPLE_RATE = 24000
const CHANNELS = 1
const BYTES_PER_SAMPLE = 2
const CHUNK_MS = 100
const CHUNK_BYTES = SAMPLE_RATE * BYTES_PER_SAMPLE * CHANNELS * (CHUNK_MS / 1000)
const QUIET_MS = 1200
const SILENCE_TAIL_MS = 3000
const MAX_SILENCE_WAIT_MS = 20000
const HARD_TIMEOUT_MS = 45000
const MODEL = 'gpt-realtime-translate'
const TRANSCRIPTION_MODEL = 'gpt-4o-mini-transcribe'
const MINT_URL = 'https://api.openai.com/v1/realtime/translations/client_secrets'
const WS_URL = `wss://api.openai.com/v1/realtime/translations?model=${MODEL}`

/// Parses `--flag value` pairs from argv into a plain object keyed by flag name.
function parseArgs(argv) {
  const out = {}
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i]
    if (!token.startsWith('--')) continue
    const key = token.slice(2)
    const value = argv[i + 1]
    out[key] = value
    i += 1
  }
  return out
}

/// Prints usage and exits with a non-zero status.
function usageError(message) {
  process.stderr.write(`${message}\n\n`)
  process.stderr.write(
    'usage: node translate_audio.mjs --in <audio file> --to <language code> --out <out.wav> [--transcript <out.json>]\n'
  )
  process.exit(1)
}

/// Reads the OpenAI API key from $OPENAI_API_KEY or ~/.openai-api-token, never logging it.
function loadApiKey() {
  const fromEnv = process.env.OPENAI_API_KEY
  if (fromEnv && fromEnv.trim()) return fromEnv.trim()
  const tokenPath = `${homedir()}/.openai-api-token`
  if (existsSync(tokenPath)) return readFileSync(tokenPath, 'utf8').trim()
  usageError('no OpenAI API key: set OPENAI_API_KEY or write ~/.openai-api-token')
}

/// Locates an ffmpeg binary, since PATH does not reliably include Homebrew's bin dir.
function resolveFfmpeg() {
  const candidates = [process.env.FFMPEG_BIN, '/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg', '/usr/bin/ffmpeg']
  for (const candidate of candidates) {
    if (candidate && existsSync(candidate)) return candidate
  }
  try {
    const found = execFileSync('which', ['ffmpeg'], { encoding: 'utf8' }).trim()
    if (found) return found
  } catch {}
  usageError('ffmpeg not found: install it or set FFMPEG_BIN')
}

/// Converts an arbitrary input audio file to raw 24 kHz mono PCM16, entirely in memory.
function convertToPcm16Mono24k(inputPath, ffmpegPath) {
  return execFileSync(
    ffmpegPath,
    ['-loglevel', 'error', '-y', '-i', inputPath, '-ar', String(SAMPLE_RATE), '-ac', String(CHANNELS), '-f', 's16le', '-'],
    { maxBuffer: 256 * 1024 * 1024 }
  )
}

/// Wraps raw PCM16 samples in a canonical 44-byte WAV header.
function writeWav(pcm, outPath) {
  const header = Buffer.alloc(44)
  const byteRate = SAMPLE_RATE * CHANNELS * BYTES_PER_SAMPLE
  const blockAlign = CHANNELS * BYTES_PER_SAMPLE
  header.write('RIFF', 0, 'ascii')
  header.writeUInt32LE(36 + pcm.length, 4)
  header.write('WAVE', 8, 'ascii')
  header.write('fmt ', 12, 'ascii')
  header.writeUInt32LE(16, 16)
  header.writeUInt16LE(1, 20)
  header.writeUInt16LE(CHANNELS, 22)
  header.writeUInt32LE(SAMPLE_RATE, 24)
  header.writeUInt32LE(byteRate, 28)
  header.writeUInt16LE(blockAlign, 32)
  header.writeUInt16LE(BYTES_PER_SAMPLE * 8, 34)
  header.write('data', 36, 'ascii')
  header.writeUInt32LE(pcm.length, 40)
  writeFileSync(outPath, Buffer.concat([header, pcm]))
}

/// Mints an ephemeral client secret exactly as mako's mint_ephemeral does: same model,
/// same output-language field, same input transcription model, no noise_reduction.
async function mintClientSecret(apiKey, outputLanguage) {
  const session = {
    model: MODEL,
    audio: {
      input: { transcription: { model: TRANSCRIPTION_MODEL } },
      output: { language: outputLanguage },
    },
  }
  const response = await fetch(MINT_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ session }),
  })
  const body = await response.json()
  if (!response.ok) {
    throw new Error(`mint rejected (${response.status}): ${body.error?.message ?? JSON.stringify(body)}`)
  }
  const value = body.value ?? body.client_secret?.value
  if (!value) throw new Error('mint response had no client secret')
  return value
}

/// Sleeps for the given number of milliseconds.
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

/// Streams `pcm` to the session paced like a live microphone (one CHUNK_MS slice per
/// CHUNK_MS of wall time), then a bounded trailing silence tail to let the server's VAD
/// register end of speech, then stops sending entirely and watches for output
/// quiescence (no output delta for QUIET_MS) or a safety timeout. Continuing to append
/// audio after the tail was found to make some sessions stream output indefinitely
/// (verified empirically: stopping the append stream is what lets a turn settle).
/// Collects the translated audio and both transcripts.
function runSession(clientSecretValue, pcm) {
  return new Promise((resolvePromise, rejectPromise) => {
    const ws = new WebSocket(WS_URL, ['realtime', `openai-insecure-api-key.${clientSecretValue}`])
    const outputAudioChunks = []
    let inputTranscript = ''
    let outputTranscript = ''
    let settled = false
    let inputSpeechSentAt = null
    let inputSpeechEndedAt = null
    let firstOutputAudioAt = null
    let lastOutputEventAt = null
    let hardTimeout = null
    let quietPoll = null

    const finish = (error) => {
      if (settled) return
      settled = true
      clearTimeout(hardTimeout)
      clearInterval(quietPoll)
      try {
        ws.close()
      } catch {}
      if (error) {
        rejectPromise(error)
        return
      }
      resolvePromise({
        outputAudio: Buffer.concat(outputAudioChunks),
        inputTranscript,
        outputTranscript,
        inputSpeechSentAt,
        inputSpeechEndedAt,
        firstOutputAudioAt,
      })
    }

    ws.onerror = (event) => finish(new Error(`websocket error: ${event.message ?? event}`))
    ws.onclose = (event) => {
      if (!settled) finish(new Error(`websocket closed early (${event.code} ${event.reason})`))
    }

    ws.onmessage = (event) => {
      let parsed
      try {
        parsed = JSON.parse(event.data)
      } catch {
        return
      }
      if (parsed.type.includes('error')) {
        finish(new Error(`session error: ${JSON.stringify(parsed).slice(0, 500)}`))
        return
      }
      lastOutputEventAt = Date.now()
      if (parsed.type.endsWith('output_audio.delta') && typeof parsed.delta === 'string') {
        if (firstOutputAudioAt === null) firstOutputAudioAt = Date.now()
        outputAudioChunks.push(Buffer.from(parsed.delta, 'base64'))
      } else if (parsed.type.endsWith('output_transcript.delta') && typeof parsed.delta === 'string') {
        outputTranscript += parsed.delta
      } else if (parsed.type.endsWith('input_transcript.delta') && typeof parsed.delta === 'string') {
        inputTranscript += parsed.delta
      }
    }

    ws.onopen = async () => {
      hardTimeout = setTimeout(() => finish(new Error('hard timeout waiting for translation')), HARD_TIMEOUT_MS)
      inputSpeechSentAt = Date.now()
      const send = (chunk) =>
        ws.send(JSON.stringify({ type: 'session.input_audio_buffer.append', audio: chunk.toString('base64') }))
      for (let offset = 0; offset < pcm.length; offset += CHUNK_BYTES) {
        send(pcm.subarray(offset, Math.min(offset + CHUNK_BYTES, pcm.length)))
        await sleep(CHUNK_MS)
      }
      inputSpeechEndedAt = Date.now()
      const silence = Buffer.alloc(CHUNK_BYTES)
      for (let sent = 0; sent < SILENCE_TAIL_MS; sent += CHUNK_MS) {
        send(silence)
        await sleep(CHUNK_MS)
      }
      if (lastOutputEventAt === null) lastOutputEventAt = Date.now()
      quietPoll = setInterval(() => {
        const sinceLastEvent = Date.now() - lastOutputEventAt
        const sinceSpeechEnded = Date.now() - inputSpeechEndedAt
        if (firstOutputAudioAt !== null && sinceLastEvent >= QUIET_MS) {
          finish(null)
        } else if (firstOutputAudioAt === null && sinceSpeechEnded >= MAX_SILENCE_WAIT_MS) {
          finish(new Error('no output audio arrived within the silence window'))
        }
      }, 100)
    }
  })
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  if (!args.in || !args.to || !args.out) {
    usageError('missing required --in, --to, or --out')
  }

  const apiKey = loadApiKey()
  const ffmpegPath = resolveFfmpeg()
  const pcm = convertToPcm16Mono24k(args.in, ffmpegPath)
  const inputDurationMs = (pcm.length / (SAMPLE_RATE * BYTES_PER_SAMPLE * CHANNELS)) * 1000

  const runStart = Date.now()
  const clientSecretValue = await mintClientSecret(apiKey, args.to)
  const result = await runSession(clientSecretValue, pcm)
  const totalMs = Date.now() - runStart

  writeWav(result.outputAudio, args.out)

  const firstAudioLatencyFromSpeechStartMs =
    result.firstOutputAudioAt !== null ? result.firstOutputAudioAt - result.inputSpeechSentAt : null
  const firstAudioLatencyFromSpeechEndMs =
    result.firstOutputAudioAt !== null ? result.firstOutputAudioAt - result.inputSpeechEndedAt : null
  const outputDurationMs = (result.outputAudio.length / (SAMPLE_RATE * BYTES_PER_SAMPLE * CHANNELS)) * 1000

  const report = {
    model: MODEL,
    outputLanguage: args.to,
    transcriptionModel: TRANSCRIPTION_MODEL,
    inputTranscript: result.inputTranscript,
    outputTranscript: result.outputTranscript,
    timing: {
      inputDurationMs: Math.round(inputDurationMs),
      outputDurationMs: Math.round(outputDurationMs),
      firstAudioLatencyMsFromSpeechStart:
        firstAudioLatencyFromSpeechStartMs === null ? null : Math.round(firstAudioLatencyFromSpeechStartMs),
      firstAudioLatencyMsFromSpeechEnd:
        firstAudioLatencyFromSpeechEndMs === null ? null : Math.round(firstAudioLatencyFromSpeechEndMs),
      totalElapsedMs: totalMs,
    },
  }

  if (args.transcript) {
    writeFileSync(args.transcript, JSON.stringify(report, null, 2))
  }

  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`)
}

main().catch((error) => {
  process.stderr.write(`error: ${error.message}\n`)
  process.exit(1)
})
