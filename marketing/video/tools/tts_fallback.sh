#!/bin/bash
set -euo pipefail
TEXT="$1"
VOICE="$2"
OUT="$3"
KEY=$(cat ~/.openai-api-token)
curl -sS https://api.openai.com/v1/audio/speech \
  -H "Authorization: Bearer ${KEY}" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c 'import json,sys; print(json.dumps({"model":"gpt-4o-mini-tts","input":sys.argv[1],"voice":sys.argv[2],"response_format":"wav"}))' "$TEXT" "$VOICE")" \
  -o "$OUT"
file "$OUT"
