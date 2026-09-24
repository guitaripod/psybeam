#!/usr/bin/env bash
# Capture the App Store screenshot set for every listing locale, and the
# per-CPP-page sets, on a dedicated simulator.
#
# Drives the DEBUG-only PSYBEAM_DEMO routes (listening, them, destination,
# coach-theirs, settings) with the simulator's language switched per locale,
# and writes raw 1320×2868 captures. Frame the output with
# scripts/frame-screenshots.swift.
#
# Usage:
#   scripts/capture-screenshots.sh [locale ...]        # listing locales (default: all 34)
#   scripts/capture-screenshots.sh --cpp [page-id ...]  # CPP pages (default: all)
#
#   PSYBEAM_SIM_NAME overrides the simulator (default "PsybeamShots" — create it
#   first with: xcrun simctl create PsybeamShots "iPhone 17 Pro Max" <runtime>).
#   PSYBEAM_SCREENS="hero reply" limits the screens captured.

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
set -a; . "$ROOT/.env.local"; set +a

SIM_NAME="${PSYBEAM_SIM_NAME:-PsybeamShots}"
BUNDLE_ID="${PSYBEAM_BUNDLE_ID}"
APP="$ROOT/build/sim/Psybeam.app"
CAPTIONS_DIR="$ROOT/marketing/captions"
CPP_PAGES_JSON="$ROOT/marketing/appstore/cpp/pages.json"
RAW_ROOT="$ROOT/marketing/appstore/raw"
SCREENS=(${PSYBEAM_SCREENS:-hero reply destination faces free})

ALL_LOCALES="ar-SA cs da de-DE el en-AU en-CA en-GB en-US es-ES es-MX fi fr-CA fr-FR he hi id it ja ko ms nl-NL no pl pt-BR pt-PT ru sv th tr uk vi zh-Hans zh-Hant"

# Screen → PSYBEAM_DEMO mode.
screen_mode() {
  case "$1" in
    hero) echo "listening" ;;
    reply) echo "them" ;;
    destination) echo "destination" ;;
    faces) echo "coach-theirs" ;;
    free) echo "settings" ;;
    *) echo "❌ unknown screen '$1'" >&2; exit 1 ;;
  esac
}

# Prints "<AppleLanguages tag> <AppleLocale>" for a listing locale — the iOS
# language that selects the right .lproj bundle, and a region for formatting.
# The traveler side of each locale's marketing/captions/<locale>.json "pair"
# picks the app's UI language; en-only App Store locales (cs, da, ms, no, uk)
# have no matching Psybeam UI translation and render in English, same as the
# app itself falls back.
apple_language_settings() {
  case "$1" in
    ar-SA)   echo "ar ar_SA" ;;
    cs)      echo "en cs_CZ" ;;
    da)      echo "en da_DK" ;;
    de-DE)   echo "de de_DE" ;;
    el)      echo "el el_GR" ;;
    en-AU)   echo "en-AU en_AU" ;;
    en-CA)   echo "en-CA en_CA" ;;
    en-GB)   echo "en-GB en_GB" ;;
    en-US)   echo "en en_US" ;;
    es-ES)   echo "es es_ES" ;;
    es-MX)   echo "es-MX es_MX" ;;
    fi)      echo "fi fi_FI" ;;
    fr-CA)   echo "fr-CA fr_CA" ;;
    fr-FR)   echo "fr fr_FR" ;;
    he)      echo "he he_IL" ;;
    hi)      echo "hi hi_IN" ;;
    id)      echo "id id_ID" ;;
    it)      echo "it it_IT" ;;
    ja)      echo "ja ja_JP" ;;
    ko)      echo "ko ko_KR" ;;
    ms)      echo "en ms_MY" ;;
    nl-NL)   echo "nl nl_NL" ;;
    no)      echo "en nb_NO" ;;
    pl)      echo "pl pl_PL" ;;
    pt-BR)   echo "pt-BR pt_BR" ;;
    pt-PT)   echo "pt-PT pt_PT" ;;
    ru)      echo "ru ru_RU" ;;
    sv)      echo "sv sv_SE" ;;
    th)      echo "th th_TH" ;;
    tr)      echo "tr tr_TR" ;;
    uk)      echo "en uk_UA" ;;
    vi)      echo "vi vi_VN" ;;
    zh-Hans) echo "zh-Hans zh_CN" ;;
    zh-Hant) echo "zh-Hant zh_TW" ;;
    *) echo "❌ unknown locale '$1'" >&2; exit 1 ;;
  esac
}

# The PSYBEAM_DEMO_PAIR spec for a listing locale: the captions file's "pair"
# (bare language codes), with the Chinese script made explicit — the app's
# own language list has one bare "zh", so DemoPhrasebook needs "zh-Hans" or
# "zh-Hant" spelled out to pick the right script for the phrase table.
demo_pair_for_locale() {
  local locale="$1"
  local pair
  pair="$(/opt/homebrew/bin/python3 -c "import json; print(json.load(open('$CAPTIONS_DIR/$locale.json'))['pair'])")"
  case "$locale" in
    zh-Hans) echo "${pair/zh:/zh-Hans:}" ;;
    zh-Hant) echo "${pair/zh:/zh-Hant:}" ;;
    *) echo "$pair" ;;
  esac
}

UDID="$(xcrun simctl list devices available -j | /opt/homebrew/bin/python3 -c "
import json,sys
devs=[d for r in json.load(sys.stdin)['devices'].values() for d in r if d['name']=='$SIM_NAME']
print(devs[0]['udid'] if devs else '')")"
if [ -z "$UDID" ]; then
  echo "❌ no simulator named '$SIM_NAME' — create it first:" >&2
  echo "   xcrun simctl create $SIM_NAME \"iPhone 17 Pro Max\" <iOS runtime>" >&2
  exit 1
fi
if [ ! -d "$APP" ]; then echo "❌ no app at $APP — build it and copy Debug-iphonesimulator Psybeam.app there" >&2; exit 1; fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --operatorName ""

capture() {
  local outdir="$1" screen="$2" lang="$3" region="$4" pair="$5"
  local mode; mode="$(screen_mode "$screen")"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  SIMCTL_CHILD_PSYBEAM_DEMO="$mode" SIMCTL_CHILD_PSYBEAM_DEMO_PAIR="$pair" \
    xcrun simctl launch \
    --terminate-running-process \
    "$UDID" "$BUNDLE_ID" \
    -AppleLanguages "($lang)" -AppleLocale "$region" >/dev/null
  sleep 3
  xcrun simctl io "$UDID" screenshot --type png "$outdir/$screen.png" >/dev/null
}

capture_set() {
  local outdir="$1" lang="$2" region="$3" pair="$4" label="$5"
  mkdir -p "$outdir"
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"
  for screen in "${SCREENS[@]}"; do
    capture "$outdir" "$screen" "$lang" "$region" "$pair"
    echo "  ✓ $label/$screen"
  done
}

if [ "${1:-}" = "--cpp" ]; then
  shift
  PAGE_IDS=()
  while IFS= read -r line; do PAGE_IDS+=("$line"); done < <(/opt/homebrew/bin/python3 -c "
import json
pages = json.load(open('$CPP_PAGES_JSON'))['pages']
ids = {
    'Japanese': 'japanese', 'Spanish': 'spanish', 'French': 'french',
    'Italian': 'italian', 'Korean': 'korean', 'Thai': 'thai',
    '接客・インバウンド向け': 'shop-staff-ja',
}
for p in pages:
    print(ids[p['name']])
")
  PAGE_FILTER="${*:-}"
  CPP_CAPTIONS_DIR="$ROOT/marketing/appstore/cpp/_captions"
  mkdir -p "$CPP_CAPTIONS_DIR"
  /opt/homebrew/bin/python3 -c "
import json
pages = json.load(open('$CPP_PAGES_JSON'))['pages']
ids = {
    'Japanese': 'japanese', 'Spanish': 'spanish', 'French': 'french',
    'Italian': 'italian', 'Korean': 'korean', 'Thai': 'thai',
    '接客・インバウンド向け': 'shop-staff-ja',
}
for p in pages:
    pid = ids[p['name']]
    with open('$CPP_CAPTIONS_DIR/' + pid + '.json', 'w') as f:
        json.dump(p['captions'], f, ensure_ascii=False, indent=2)
"
  for i in "${!PAGE_IDS[@]}"; do
    page_id="${PAGE_IDS[$i]}"
    if [ -n "$PAGE_FILTER" ] && [[ ! " $PAGE_FILTER " =~ " $page_id " ]]; then continue; fi
    pair="$(/opt/homebrew/bin/python3 -c "
import json
pages = json.load(open('$CPP_PAGES_JSON'))['pages']
print(pages[$i]['pair'])")"
    page_locale="$(/opt/homebrew/bin/python3 -c "
import json
pages = json.load(open('$CPP_PAGES_JSON'))['pages']
print(pages[$i]['locale'])")"
    read -r lang region <<< "$(apple_language_settings "$page_locale")"
    capture_set "$RAW_ROOT/cpp/$page_id" "$lang" "$region" "$pair" "cpp/$page_id"
  done
  echo "cpp captions written to $CPP_CAPTIONS_DIR (frame with --captions $CPP_CAPTIONS_DIR --raw $RAW_ROOT/cpp --out $ROOT/marketing/appstore/cpp)"
else
  LOCALES="${*:-$ALL_LOCALES}"
  for locale in $LOCALES; do
    read -r lang region <<< "$(apple_language_settings "$locale")"
    pair="$(demo_pair_for_locale "$locale")"
    capture_set "$RAW_ROOT/$locale" "$lang" "$region" "$pair" "$locale"
  done
fi

/opt/homebrew/bin/python3 - "$RAW_ROOT" <<'EOF'
import os, struct, sys
root = sys.argv[1]
bad = []
for dirpath, _, files in os.walk(root):
    for f in files:
        if not f.endswith(".png"): continue
        path = os.path.join(dirpath, f)
        with open(path, "rb") as fh:
            fh.seek(16); w, h = struct.unpack(">II", fh.read(8))
        if (w, h) != (1320, 2868): bad.append((path, w, h))
if bad:
    print("❌ wrong size:", bad); sys.exit(1)
print("✅ all captures are 1320×2868")
EOF
