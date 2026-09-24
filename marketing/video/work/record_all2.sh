#!/bin/bash
set -uo pipefail
WORK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UDID=$(cat "$WORK/recorder_udid.txt")
mkdir -p "$WORK/raw"

record_one() {
  local sid="$1" pair="$2" script="$3" total="$4"
  local record_dur
  record_dur=$(python3 -c "print(round(2.2 + $total + 1.6, 1))")
  rm -f "$WORK/raw/${sid}.mov"
  xcrun simctl io "$UDID" recordVideo --codec h264 --force "$WORK/raw/${sid}.mov" &
  local rec_pid=$!
  sleep 1.2
  SIMCTL_CHILD_PSYBEAM_DEMO=script \
    SIMCTL_CHILD_PSYBEAM_DEMO_PAIR="$pair" \
    SIMCTL_CHILD_PSYBEAM_DEMO_SCRIPT="$script" \
    xcrun simctl launch --terminate-running-process "$UDID" com.guitaripod.psybeam \
    -AppleLanguages "(en)" -AppleLocale en_US > /dev/null
  sleep "$record_dur"
  kill -INT "$rec_pid"
  wait "$rec_pid"
  echo "recorded $sid -> $WORK/raw/${sid}.mov"
}

while read -r sid pair script total; do
  record_one "$sid" "$pair" "$script" "$total"
done < "$1"
