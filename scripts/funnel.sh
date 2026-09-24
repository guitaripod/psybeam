#!/usr/bin/env bash
set -euo pipefail

readonly MAKO_DIR="$HOME/Dev/rust/mako"
readonly DB_NAME="openai-image-proxy"
readonly APP_ID="psybeam"

print_usage() {
  echo "Usage: $(basename "$0") --since YYYY-MM-DD" >&2
}

parse_since_arg() {
  local since=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since)
        [[ $# -ge 2 ]] || { print_usage; exit 1; }
        since="$2"
        shift 2
        ;;
      *)
        print_usage
        exit 1
        ;;
    esac
  done
  if [[ -z "$since" || ! "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    print_usage
    exit 1
  fi
  echo "$since"
}

require_tools() {
  command -v jq >/dev/null 2>&1 || { echo "error: jq is required" >&2; exit 1; }
  command -v wrangler >/dev/null 2>&1 || { echo "error: wrangler is required on PATH" >&2; exit 1; }
}

run_d1_query() {
  local sql="$1"
  (cd "$MAKO_DIR" && wrangler d1 execute "$DB_NAME" --remote --json --command "$sql")
}

scalar_from_query() {
  local sql="$1"
  run_d1_query "$sql" | jq -r '.[0].results[0].n // 0'
}

count_wallets_created() {
  local since="$1"
  scalar_from_query \
    "SELECT COUNT(*) AS n FROM users WHERE app_id='${APP_ID}' AND created_at >= '${since}';"
}

count_wallets_with_session() {
  local since="$1"
  scalar_from_query \
    "SELECT COUNT(DISTINCT user_id) AS n FROM realtime_sessions WHERE app_id='${APP_ID}' AND created_at >= '${since}';"
}

count_wallets_activated() {
  local since="$1"
  scalar_from_query \
    "SELECT COUNT(DISTINCT user_id) AS n FROM realtime_sessions WHERE app_id='${APP_ID}' AND settled=1 AND actual_minutes > 0 AND created_at >= '${since}';"
}

count_wallets_returned() {
  local since="$1"
  scalar_from_query \
    "SELECT COUNT(*) AS n FROM (
       SELECT user_id FROM realtime_sessions
       WHERE app_id='${APP_ID}' AND settled=1 AND actual_minutes > 0 AND created_at >= '${since}'
       GROUP BY user_id
       HAVING COUNT(DISTINCT substr(created_at, 1, 10)) >= 2
     );"
}

count_wallets_hit_paywall() {
  local since="$1"
  scalar_from_query \
    "SELECT COUNT(DISTINCT user_id) AS n FROM paywall_events WHERE app_id='${APP_ID}' AND created_at >= '${since}';"
}

sum_billed_minutes() {
  local since="$1"
  scalar_from_query \
    "SELECT COALESCE(SUM(actual_minutes), 0) AS n FROM realtime_sessions WHERE app_id='${APP_ID}' AND settled=1 AND created_at >= '${since}';"
}

cents_to_dollars() {
  local cents="$1"
  awk -v c="$cents" 'BEGIN { printf "%.2f", c / 100 }'
}

print_purchases_by_pack() {
  local since="$1"
  local sql="SELECT pack_id, COUNT(*) AS purchases, SUM(amount_usd_cents) AS cents
             FROM credit_purchases
             WHERE app_id='${APP_ID}' AND status='completed' AND completed_at >= '${since}'
             GROUP BY pack_id
             ORDER BY pack_id;"
  local rows
  rows="$(run_d1_query "$sql" | jq -c '.[0].results[]')"
  if [[ -z "$rows" ]]; then
    echo "  none"
    return
  fi
  local row pack purchases cents
  while IFS= read -r row; do
    pack="$(jq -r '.pack_id' <<< "$row")"
    purchases="$(jq -r '.purchases' <<< "$row")"
    cents="$(jq -r '.cents' <<< "$row")"
    echo "  ${pack}: ${purchases} purchases, \$$(cents_to_dollars "$cents")"
  done <<< "$rows"
}

print_report() {
  local since="$1"
  echo "Psybeam funnel since ${since}"
  echo "-----------------------------"
  echo "Wallets created:               $(count_wallets_created "$since")"
  echo "Wallets with >=1 session:      $(count_wallets_with_session "$since")"
  echo "Wallets activated (>=1 min):   $(count_wallets_activated "$since")"
  echo "Wallets returned (2+ days):    $(count_wallets_returned "$since")"
  echo "Wallets hit paywall:           $(count_wallets_hit_paywall "$since")"
  echo "Total billed minutes:          $(sum_billed_minutes "$since")"
  echo "Purchases (completed, by pack):"
  print_purchases_by_pack "$since"
}

main() {
  require_tools
  local since
  since="$(parse_since_arg "$@")"
  print_report "$since"
}

main "$@"
