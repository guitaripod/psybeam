#!/bin/bash
set -euo pipefail
FF=/opt/homebrew/bin/ffmpeg
NODE=/opt/homebrew/bin/node
ROOT=/Users/marcus/Dev/ios/psybeam/marketing/video
TOOLS="$ROOT/tools"
ASSETS="$ROOT/assets"

STORY="$1"
NAME="$2"
LANG="$3"

MP4="$ASSETS/$STORY/shots/${NAME}.mp4"
SRC_WAV="$ASSETS/$STORY/audio/${NAME}_source.wav"
OUT_WAV="$ASSETS/$STORY/audio/${NAME}_translated_${LANG}.wav"
OUT_JSON="$ASSETS/$STORY/audio/${NAME}_translated_${LANG}.json"

mkdir -p "$ASSETS/$STORY/audio"
"$FF" -y -loglevel error -i "$MP4" -vn -acodec pcm_s16le -ar 24000 -ac 1 "$SRC_WAV"
"$NODE" "$TOOLS/translate_audio.mjs" --in "$SRC_WAV" --to "$LANG" --out "$OUT_WAV" --transcript "$OUT_JSON"
