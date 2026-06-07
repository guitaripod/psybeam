#!/usr/bin/env bash
# Build + install + relaunch Psybeam on the connected iPhone.
#
# Wraps scripts/ios-build.sh (which already asserts the build is fresh), then
# installs, terminates any running instance, and relaunches the bundle.
#
# Usage: scripts/ios-deploy.sh [UDID]
#   Default device: PSYBEAM_DEVICE_UDID from .env.local.

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

if [ ! -f "$ROOT/.env.local" ]; then
  echo "❌ Missing .env.local — run scripts/setup.sh first." >&2
  exit 1
fi
set -a; . "$ROOT/.env.local"; set +a

UDID="${1:-${PSYBEAM_DEVICE_UDID:-}}"
if [ -z "$UDID" ]; then
  echo "❌ No device UDID. Pass one as the first argument or set PSYBEAM_DEVICE_UDID in .env.local." >&2
  exit 1
fi
BUNDLE_ID="${PSYBEAM_BUNDLE_ID:?set PSYBEAM_BUNDLE_ID in .env.local}"

APP="$(scripts/ios-build.sh "platform=iOS,id=$UDID" | tail -1)"
if [ ! -d "$APP" ]; then
  echo "❌ Build did not yield an app bundle." >&2
  exit 1
fi

echo "▸ installing on $UDID"
xcrun devicectl device install app --device "$UDID" "$APP" 2>&1 | grep -E "installed|bundleID|error:" | head -3 || true

echo "▸ relaunching $BUNDLE_ID"
xcrun devicectl device process terminate --device "$UDID" --bundle-identifier "$BUNDLE_ID" 2>/dev/null || true
xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID" \
  2>&1 | grep -v "Acquired\|Enabling\|Failed to load\|manage create" | tail -2 || true

echo "▸ deployed."
