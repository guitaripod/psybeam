#!/usr/bin/env bash
# One-time local setup for Psybeam.
#
# - Creates .env.local from .env.local.example if missing (auto-detecting the
#   signing Team ID when possible).
# - Copies Psybeam/Secrets.example.swift -> Psybeam/Secrets.swift if missing.
# - Regenerates Psybeam.xcodeproj from project.yml (xcodegen).
# - Resolves the local PsybeamKit package + GRDB.
#
# Safe to re-run.

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

echo "==> Psybeam setup"

if [ ! -f .env.local ]; then
  if [ ! -f .env.local.example ]; then
    echo "error: .env.local.example missing — cannot bootstrap .env.local" >&2
    exit 1
  fi
  echo "==> Creating .env.local from .env.local.example"
  TEAM_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -oE '\(([A-Z0-9]{10})\)' | head -1 | tr -d '()' || true)"
  if [ -n "$TEAM_ID" ]; then
    sed "s|^PSYBEAM_TEAM_ID=.*$|PSYBEAM_TEAM_ID=$TEAM_ID|" .env.local.example > .env.local
  else
    cp .env.local.example .env.local
  fi
  chmod 600 .env.local
  echo "    edit .env.local: set PSYBEAM_TEAM_ID + device values"
else
  echo "·  .env.local already exists, leaving it"
fi

if [ ! -f Psybeam/Secrets.swift ]; then
  echo "==> Creating Psybeam/Secrets.swift from example"
  cp Psybeam/Secrets.example.swift Psybeam/Secrets.swift
  echo "    edit Psybeam/Secrets.swift: workerBaseURL + redirectURI"
else
  echo "·  Psybeam/Secrets.swift already exists, leaving it"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not installed (brew install xcodegen)." >&2
  exit 1
fi

echo "==> xcodegen generate"
xcodegen generate

echo "==> swift package resolve"
swift package resolve >/dev/null 2>&1 || true

echo "==> Done. Next: edit .env.local + Psybeam/Secrets.swift, then scripts/ios-build.sh"
