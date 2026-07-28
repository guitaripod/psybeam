#!/usr/bin/env bash
set -euo pipefail

# Spike 6 (RESOLVED 2026-07-29): what the /v1/realtime/translations transport actually
# emits. Answers two questions the app's transcript plumbing depends on: (1) do
# input_transcript deltas arrive without an explicit input-transcription model, and
# (2) is there ANY closing/done event to mark end of turn. Drives a real WebSocket
# session per candidate transcription model with synthesized speech, then a long tail
# of silence. The key is read from $OPENAI_API_KEY or ~/.openai-api-token and is NEVER
# printed or written. Costs ~$0.003 of translate time per model probed.

readonly HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PCM="/tmp/psybeam-spike6.pcm"
readonly PHRASE="Excuse me, where is the train station? I need to catch the six oclock train."
readonly MODELS=(none gpt-live-transcribe gpt-transcribe gpt-4o-transcribe gpt-4o-mini-transcribe whisper-1)

die() { printf 'error: %s\n' "$1" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

synthesize() {
  [[ -f "${PCM}" ]] && return 0
  need say; need ffmpeg
  say -v Samantha -o /tmp/psybeam-spike6.aiff "${PHRASE}"
  ffmpeg -loglevel error -y -i /tmp/psybeam-spike6.aiff -ar 24000 -ac 1 -f s16le "${PCM}"
}

main() {
  need node
  [[ -n "${OPENAI_API_KEY:-}" || -f "${HOME}/.openai-api-token" ]] \
    || die "no key: set OPENAI_API_KEY or write ~/.openai-api-token"
  synthesize
  printf '== Spike 6: translations transcript events ==\nspeech: %s\n' "${PCM}"
  for model in "${MODELS[@]}"; do
    printf '\n---------------- input transcription: %s\n' "${model}"
    node "${HERE}/probe.mjs" "--transcribe=${model}" "--pcm=${PCM}" "$@"
  done
}

main "$@"
