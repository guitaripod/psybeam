#!/usr/bin/env bash
set -euo pipefail

# Spike 1 (RESOLVED 2026-06-07): gpt-realtime-translate is served under the dedicated
# /v1/realtime/translations namespace. This probe mints an ephemeral client secret per
# candidate output language at that endpoint and reports acceptance. Mint-only: no SDP,
# no audio. The key is read from $OPENAI_API_KEY or ~/.openai-api-token and is NEVER
# printed or written. Full translation behavior was verified separately (see README).

readonly MINT_URL="https://api.openai.com/v1/realtime/translations/client_secrets"
readonly MODEL="gpt-realtime-translate"
readonly TOKEN_FILE="${HOME}/.openai-api-token"
readonly CANDIDATES=(es pt fr de it nl en ru pl tr el ar he hi ja ko zh th vi id fi sv)

die() { printf 'error: %s\n' "$1" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

load_key() {
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then KEY="${OPENAI_API_KEY}"; KEY_SOURCE="OPENAI_API_KEY env var"; return 0; fi
  if [[ -f "${TOKEN_FILE}" ]]; then
    KEY="$(tr -d '[:space:]' < "${TOKEN_FILE}")"; KEY_SOURCE="${TOKEN_FILE}"
    [[ -n "${KEY}" ]] || die "${TOKEN_FILE} is empty"; return 0
  fi
  cat >&2 <<EOF
No OpenAI key found. Supply one of:
  OPENAI_API_KEY=sk-... ./run.sh
  printf '%s' 'sk-...' > ${TOKEN_FILE} && chmod 600 ${TOKEN_FILE} && ./run.sh
The key is never printed and never written by this script.
EOF
  exit 2
}

probe() {
  local lang="$1" body resp http json
  body="$(printf '{"session":{"model":"%s","audio":{"output":{"language":"%s"}}}}' "${MODEL}" "${lang}")"
  resp="$(curl -sS --max-time 30 -w $'\n%{http_code}' \
    -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" \
    -X POST "${MINT_URL}" -d "${body}" 2>/dev/null || true)"
  http="${resp##*$'\n'}"; json="${resp%$'\n'*}"
  [[ "${http}" =~ ^[0-9]+$ ]] || http="000"
  local has_token="no" err=""
  if [[ "${http}" == "200" ]]; then
    printf '%s' "${json}" | jq -e '.value // .client_secret.value' >/dev/null 2>&1 && has_token="yes"
  else
    err="$(printf '%s' "${json}" | jq -r '.error.message // empty' 2>/dev/null || true)"
    [[ -n "${err}" ]] || err="(no error message)"
  fi
  printf '%s\t%s\t%s\t%s\n' "${lang}" "${http}" "${has_token}" "${err}"
}

main() {
  need curl; need jq; load_key
  printf '== Spike 1: translations mint probe ==\n'
  printf 'mint:  %s\nmodel: %s\nkey:   loaded from %s (value not shown)\n\n' "${MINT_URL}" "${MODEL}" "${KEY_SOURCE}"
  printf '%-6s %-6s %-9s %s\n%-6s %-6s %-9s %s\n' LANG HTTP ACCEPTED NOTE ---- ---- -------- ----
  local accepted=() other=() lang http has_token err line
  for lang in "${CANDIDATES[@]}"; do
    line="$(probe "${lang}")"; IFS=$'\t' read -r lang http has_token err <<<"${line}"
    if [[ "${http}" == "200" && "${has_token}" == "yes" ]]; then
      accepted+=("${lang}"); printf '%-6s %-6s %-9s %s\n' "${lang}" "${http}" yes "minted ek_ ok"
    else
      other+=("${lang}"); printf '%-6s %-6s %-9s %s\n' "${lang}" "${http}" no "${err}"
    fi
  done
  printf '\nACCEPTED: %s\n' "${accepted[*]:-(none)}"
  (( ${#other[@]} > 0 )) && printf 'OTHER:    %s\n' "${other[*]}"
}

main "$@"
