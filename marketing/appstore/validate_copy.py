#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import glob
import json
import os
import string
import sys

BASE = os.path.dirname(os.path.abspath(__file__))
APPINFO_DIR = f"{BASE}/metadata/app-info"
VERSION_DIR = f"{BASE}/metadata/version/1.1.1"
CAPTIONS_DIR = os.path.join(os.path.dirname(BASE), "captions")
CPP_PATH = f"{BASE}/cpp/pages.json"
EVENTS_DIR = f"{BASE}/events"

NAME_LIMIT = 30
SUBTITLE_LIMIT = 30
KEYWORDS_LIMIT = 100
PROMO_LIMIT = 170
WHATS_NEW_LIMIT = 4000
CPP_PROMO_LIMIT = 170
EVENT_NAME_LIMIT = 30
EVENT_SHORT_LIMIT = 50
EVENT_LONG_LIMIT = 120

TOKEN_STRIP = string.punctuation + "：，。、•！？「」『』ー・؛،؟"

COMPETITOR_TRADEMARKS = [
    "google translate",
    "itranslate",
    "microsoft translator",
    "deepl",
    "papago",
    "naver",
    "speak & translate",
    "voiceitt",
    "otter.ai",
]


class Check:
    """A single pass/fail row destined for the printed report table."""

    def __init__(self, area, locale, field, detail, passed):
        self.area = area
        self.locale = locale
        self.field = field
        self.detail = detail
        self.passed = passed


def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def name_and_subtitle_words(locale):
    """Return the lowercased whitespace-delimited tokens of a locale's app name and subtitle."""
    info = load_json(f"{APPINFO_DIR}/{locale}.json")
    tokens = set()
    for text in (info["name"], info["subtitle"]):
        for token in text.split():
            stripped = token.strip(TOKEN_STRIP).lower()
            if stripped and stripped != "psybeam":
                tokens.add(stripped)
    return tokens


def keyword_terms(keywords):
    return [term for term in keywords.split(",")]


def check_keyword_formatting(locale, keywords):
    checks = []
    no_bad_spacing = ", " not in keywords and keywords == keywords.strip() and ",," not in keywords
    checks.append(Check("keywords", locale, "comma spacing", "no space after commas, no leading/trailing space", no_bad_spacing))
    lowered = keywords.lower()
    hit_trademark = next((term for term in COMPETITOR_TRADEMARKS if term in lowered), None)
    checks.append(Check("keywords", locale, "no competitor trademarks", hit_trademark or "clean", hit_trademark is None))
    return checks


def check_keyword_overlap(locale, keywords):
    banned = name_and_subtitle_words(locale)
    overlaps = []
    for term in keyword_terms(keywords):
        term_words = {token.strip(TOKEN_STRIP).lower() for token in term.split() if token.strip(TOKEN_STRIP)}
        hit = term_words & banned
        if hit:
            overlaps.append((term, hit))
    detail = "clean" if not overlaps else f"{overlaps}"
    return Check("keywords", locale, "no name/subtitle words", detail, not overlaps)


def check_mandatory_terms(locale, keywords, required):
    terms = set(keyword_terms(keywords))
    missing = [term for term in required if term not in terms]
    detail = "present" if not missing else f"missing {missing}"
    return Check("keywords", locale, "mandatory destination terms", detail, not missing)


def check_length(area, locale, field, value, limit):
    length = len(value)
    return Check(area, locale, field, f"{length}/{limit}", length <= limit)


def validate_version_1_1_1():
    checks = []
    locales = sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(f"{VERSION_DIR}/*.json"))
    for locale in locales:
        data = load_json(f"{VERSION_DIR}/{locale}.json")
        info = load_json(f"{APPINFO_DIR}/{locale}.json")
        checks.append(check_length("app-info", locale, "name", info["name"], NAME_LIMIT))
        checks.append(check_length("app-info", locale, "subtitle", info["subtitle"], SUBTITLE_LIMIT))
        checks.append(check_length("version/1.1.1", locale, "keywords", data["keywords"], KEYWORDS_LIMIT))
        checks.append(check_length("version/1.1.1", locale, "promotionalText", data["promotionalText"], PROMO_LIMIT))
        checks.append(check_length("version/1.1.1", locale, "whatsNew", data["whatsNew"], WHATS_NEW_LIMIT))
        checks.extend(check_keyword_formatting(locale, data["keywords"]))
        checks.append(check_keyword_overlap(locale, data["keywords"]))
        for field in ("description", "supportUrl", "marketingUrl"):
            checks.append(Check("version/1.1.1", locale, field, "present", bool(data.get(field))))
    if "en-US" in locales:
        en_us = load_json(f"{VERSION_DIR}/en-US.json")
        checks.append(check_mandatory_terms(
            "en-US", en_us["keywords"],
            ["japanese", "spanish", "french", "italian", "korean", "thai"],
        ))
    if "ja" in locales:
        ja = load_json(f"{VERSION_DIR}/ja.json")
        checks.append(check_mandatory_terms("ja", ja["keywords"], ["接客", "インバウンド"]))
    return checks, locales


def validate_captions(expected_locales):
    checks = []
    found = sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(f"{CAPTIONS_DIR}/*.json"))
    missing = sorted(set(expected_locales) - set(found))
    checks.append(Check("captions", "*", "all listing locales present", f"missing {missing}" if missing else "complete", not missing))
    for locale in found:
        data = load_json(f"{CAPTIONS_DIR}/{locale}.json")
        traveler, local = data["pair"].split(":")
        checks.append(Check("captions", locale, "pair traveler != local", data["pair"], traveler != local))
        for frame in data.get("order", []):
            frame_data = data.get(frame, {})
            has_both = bool(frame_data.get("title")) and bool(frame_data.get("subtitle"))
            checks.append(Check("captions", locale, f"{frame} has title+subtitle", "present" if has_both else "missing", has_both))
    return checks


def validate_cpp():
    checks = []
    if not os.path.exists(CPP_PATH):
        return [Check("cpp", "*", "pages.json exists", "missing", False)]
    data = load_json(CPP_PATH)
    pages = data.get("pages", [])
    checks.append(Check("cpp", "*", "page count", f"{len(pages)}", len(pages) == 7))
    seen_keywords = []
    for page in pages:
        name = page.get("name", "?")
        checks.append(check_length("cpp", name, "promotionalText", page["promotionalText"], CPP_PROMO_LIMIT))
        seen_keywords.extend(page.get("keywords", []))
        captions = page.get("captions", {})
        for frame in captions.get("order", []):
            frame_data = captions.get(frame, {})
            has_both = bool(frame_data.get("title")) and bool(frame_data.get("subtitle"))
            checks.append(Check("cpp", name, f"{frame} has title+subtitle", "present" if has_both else "missing", has_both))
    duplicates = {term for term in seen_keywords if seen_keywords.count(term) > 1}
    checks.append(Check("cpp", "*", "no keyword overlap between pages", "clean" if not duplicates else f"duplicated {duplicates}", not duplicates))
    return checks


def validate_events():
    checks = []
    paths = sorted(glob.glob(f"{EVENTS_DIR}/*.json"))
    if not paths:
        return [Check("events", "*", "an event file exists", "missing", False)]
    for path in paths:
        data = load_json(path)
        slug = os.path.basename(path)
        checks.append(Check("events", slug, "referenceName <= 64", f"{len(data.get('referenceName', ''))}/64", len(data.get("referenceName", "")) <= 64))
        for locale, copy in data.get("localizations", {}).items():
            checks.append(check_length("events", f"{slug}:{locale}", "name", copy["name"], EVENT_NAME_LIMIT))
            checks.append(check_length("events", f"{slug}:{locale}", "shortDescription", copy["shortDescription"], EVENT_SHORT_LIMIT))
            checks.append(check_length("events", f"{slug}:{locale}", "longDescription", copy["longDescription"], EVENT_LONG_LIMIT))
    return checks


def print_table(title, checks):
    print(f"\n=== {title} ===")
    width_area = max((len(c.area) for c in checks), default=4)
    width_locale = max((len(c.locale) for c in checks), default=6)
    width_field = max((len(c.field) for c in checks), default=5)
    for check in checks:
        status = "PASS" if check.passed else "FAIL"
        print(f"{status:4}  {check.area:<{width_area}}  {check.locale:<{width_locale}}  {check.field:<{width_field}}  {check.detail}")


def main():
    all_checks = []

    metadata_checks, locales = validate_version_1_1_1()
    all_checks.extend(metadata_checks)
    print_table("metadata/version/1.1.1 + app-info", metadata_checks)

    caption_checks = validate_captions(locales)
    all_checks.extend(caption_checks)
    print_table("captions", caption_checks)

    cpp_checks = validate_cpp()
    all_checks.extend(cpp_checks)
    print_table("cpp/pages.json", cpp_checks)

    event_checks = validate_events()
    all_checks.extend(event_checks)
    print_table("events", event_checks)

    failures = [c for c in all_checks if not c.passed]
    print(f"\n{len(all_checks) - len(failures)}/{len(all_checks)} checks passed")
    if failures:
        print(f"{len(failures)} FAILING:")
        for check in failures:
            print(f"  [{check.area}] {check.locale} / {check.field}: {check.detail}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
