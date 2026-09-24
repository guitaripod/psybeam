#!/bin/bash
set -uo pipefail
WORK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UDID=$(cat "$WORK/recorder_udid.txt")
mkdir -p "$WORK/raw"

record_script() {
  local name="$1" pair="$2" script="$3" total="$4" langs="$5" locale="$6"
  local record_dur
  record_dur=$(python3 -c "print(round(2.2 + $total + 1.6, 1))")
  rm -f "$WORK/raw/${name}.mov"
  xcrun simctl io "$UDID" recordVideo --codec h264 --force "$WORK/raw/${name}.mov" &
  local rec_pid=$!
  sleep 1.2
  SIMCTL_CHILD_PSYBEAM_DEMO=script \
    SIMCTL_CHILD_PSYBEAM_DEMO_PAIR="$pair" \
    SIMCTL_CHILD_PSYBEAM_DEMO_SCRIPT="$script" \
    xcrun simctl launch --terminate-running-process "$UDID" com.guitaripod.psybeam \
    -AppleLanguages "($langs)" -AppleLocale "$locale" > /dev/null
  sleep "$record_dur"
  kill -INT "$rec_pid"
  wait "$rec_pid"
  echo "recorded $name"
}

record_static() {
  local name="$1" demo="$2" pair="$3" langs="$4" locale="$5" dur="$6"
  rm -f "$WORK/raw/${name}.mov"
  xcrun simctl io "$UDID" recordVideo --codec h264 --force "$WORK/raw/${name}.mov" &
  local rec_pid=$!
  sleep 1.0
  SIMCTL_CHILD_PSYBEAM_DEMO="$demo" \
    SIMCTL_CHILD_PSYBEAM_DEMO_PAIR="$pair" \
    xcrun simctl launch --terminate-running-process "$UDID" com.guitaripod.psybeam \
    -AppleLanguages "($langs)" -AppleLocale "$locale" > /dev/null
  sleep "$dur"
  kill -INT "$rec_pid"
  wait "$rec_pid"
  echo "recorded $name"
}

record_script preview-en en:ja "$WORK/demo-scripts/preview-en.json" 14.0 en en_US
record_script preview-ja ja:en "$WORK/demo-scripts/preview-ja.json" 13.43 ja ja_JP
record_static destination-en destination en:ja en en_US 3.0
record_static destination-ja destination ja:en ja ja_JP 3.0
