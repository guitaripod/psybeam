#!/usr/bin/env bash
set -euo pipefail

# Runs both test suites:
#   1. PsybeamKit (SPM) — pure logic incl. the cause-accurate failure mapping. Linux + macOS.
#   2. Psybeam (hosted iOS unit tests) — TranslationLeg state machine, driven through a
#      mock RealtimeCallProviding on a simulator.
#
# Override the simulator with PSYBEAM_SIM_UDID; otherwise the first available iPhone is used.

cd "$(dirname "$0")/.."

echo "== PsybeamKit (SPM) =="
swift test

echo "== Psybeam iOS tests (simulator) =="
xcodegen generate >/dev/null

SIM="${PSYBEAM_SIM_UDID:-$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
udid = next((d["udid"] for runtime, ds in devices.items() if "iOS" in runtime
             for d in ds if d.get("isAvailable") and "iPhone" in d["name"]), "")
print(udid)
')}"

if [[ -z "${SIM}" ]]; then
  echo "error: no available iPhone simulator found" >&2
  exit 1
fi

xcrun simctl boot "${SIM}" 2>/dev/null || true
xcrun simctl bootstatus "${SIM}" -b >/dev/null 2>&1 || true
xcodebuild -project Psybeam.xcodeproj -scheme Psybeam \
  -destination "id=${SIM}" -derivedDataPath build/dd \
  test CODE_SIGNING_ALLOWED=NO
