import json
import subprocess

FP = "/opt/homebrew/bin/ffprobe"
ASSETS = "/Users/marcus/Dev/ios/psybeam/marketing/video/assets"

STORIES = [
    "tokyo-ramen", "cdmx-tacos", "paris-bakery", "rome-trattoria",
    "bangkok-market", "seoul-pharmacy", "kyoto-shop",
]

LANG = json.load(open("/Users/marcus/Dev/ios/psybeam/marketing/video/work/lang_map.json"))

DESCRIPTIONS = {
    "tokyo-ramen": {
        "1_establish": "Wide two-shot: traveler sits at a Tokyo ramen counter at night as the chef works behind it, steam rising.",
        "2_traveler": "Traveler leans in, phone glowing, orders in English: \"Hi! One tonkotsu ramen, not too spicy, please.\"",
        "3_local": "Chef nods and replies in Japanese: \"かしこまりました。少々お待ちください。\"",
        "4_payoff": "Bowl arrives; traveler eats with chopsticks, smiling, Tokyo street lights behind her.",
    },
    "cdmx-tacos": {
        "1_establish": "Wide two-shot: traveler steps up to a Mexico City taco stand at dusk as the taquero works the grill.",
        "2_traveler": "Traveler holds up his phone, orders in English: \"Three al pastor tacos, one without onion, please.\"",
        "3_local": "Taquero smiles, replies in Spanish: \"¡Claro! ¿Con salsa verde o roja?\"",
        "4_payoff": "Plate of tacos slides across the counter; traveler smiles, about to bite.",
    },
    "paris-bakery": {
        "1_establish": "Wide two-shot: traveler steps up to a Paris boulangerie counter in the morning as the baker arranges croissants.",
        "2_traveler": "Traveler holds up her phone, asks in English: \"Two croissants and a baguette, please. Is this one still warm?\"",
        "3_local": "Baker smiles, replies in French: \"Oui, elle sort du four à l'instant !\"",
        "4_payoff": "Baker hands over a bag of pastries; traveler smiles, holding it close.",
    },
    "rome-trattoria": {
        "1_establish": "Wide shot: a couple at a Rome trattoria terrace table as the waiter approaches with a notepad. Note: a second background figure resembling a waiter is visible seated at the table in this take — usable but worth a look before final cut.",
        "2_traveler": "The couple orders in English: \"We'd love the cacio e pepe and a carafe of house red.\"",
        "3_local": "Waiter nods, replies in Italian: \"Ottima scelta, arriva subito.\"",
        "4_payoff": "Carafe of red wine arrives; the couple lean in together, smiling.",
    },
    "bangkok-market": {
        "1_establish": "Wide two-shot: traveler steps up to a Bangkok night-market wok stall as the vendor tosses noodles in flame.",
        "2_traveler": "Traveler holds up his phone, orders in English: \"One pad thai, medium spicy, with extra lime please.\"",
        "3_local": "Vendor smiles, replies in Thai: \"ได้ค่ะ รอสักครู่นะคะ\"",
        "4_payoff": "Plate of pad thai with lime slides across; traveler smiles, steam rising.",
    },
    "seoul-pharmacy": {
        "1_establish": "Wide two-shot: traveler steps up to a Seoul pharmacy counter, hand at her throat, as the pharmacist looks up.",
        "2_traveler": "Traveler gestures at her throat, phone glowing, asks in English: \"Do you have something for a sore throat?\"",
        "3_local": "Pharmacist nods, replies in Korean: \"네, 이 목캔디랑 이 약을 추천해요.\"",
        "4_payoff": "Pharmacist sets medicine and throat candy on the counter; traveler smiles, reaching for them.",
    },
    "kyoto-shop": {
        "1_establish": "Wide two-shot: a foreign tourist browses a Kyoto souvenir shop as the shopkeeper (the operator, holding the phone) looks on.",
        "2_traveler": "Tourist holds up a folded textile, asks in English: \"Do you have this in a smaller size?\"",
        "3_local": "Shopkeeper looks at his phone, then replies slowly and clearly in Japanese: \"はい、こちらに小さいサイズがございます。\" (regenerated twice: once to fix the customer's ethnicity/role — v1 read as an ambiguous local, not a foreign tourist — and once more with a slower, clearly-enunciated line after the first take's dialogue audio was too indistinct for the transcription model to hear \"小さい\" correctly).",
        "4_payoff": "Shopkeeper sets down a smaller folded textile; tourist smiles, picking it up to compare.",
    },
}

SPEAKER_BY_ROLE = {"1_establish": None, "2_traveler": "traveler", "3_local": "local", "4_payoff": None}
HAS_DIALOGUE_BY_ROLE = {"1_establish": False, "2_traveler": True, "3_local": True, "4_payoff": False}

def ffprobe_duration(path):
    out = subprocess.run(
        [FP, "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
        capture_output=True, text=True, check=True,
    )
    return round(float(out.stdout.strip()), 2)

def rel(path):
    return path.replace("/Users/marcus/Dev/ios/psybeam/marketing/video/assets/", "")

manifest = {"generated": "2026-09-24", "resolution": "1088x1920", "fps": 24, "model": "LTX-2.5 distilled (text-to-video + image-to-video chaining)", "translation_model": "gpt-realtime-translate (same session config as production mako mint)", "stories": []}

total_openai_seconds = 0.0

for story in STORIES:
    lang = LANG[story]
    shots = []
    for role in ["1_establish", "2_traveler", "3_local", "4_payoff"]:
        name = f"{story}_{role}"
        path = f"{ASSETS}/{story}/shots/{name}.mp4"
        shots.append({
            "file": rel(path),
            "duration_s": ffprobe_duration(path),
            "description": DESCRIPTIONS[story][role],
            "has_dialogue": HAS_DIALOGUE_BY_ROLE[role],
            "speaker": SPEAKER_BY_ROLE[role],
        })

    translations = []
    for role, target_lang, label in [("2_traveler", lang, "traveler -> local"), ("3_local", "en", "local -> traveler")]:
        src_wav = f"{ASSETS}/{story}/audio/{story}_{role}_source.wav"
        out_wav = f"{ASSETS}/{story}/audio/{story}_{role}_translated_{target_lang}.wav"
        out_json = f"{ASSETS}/{story}/audio/{story}_{role}_translated_{target_lang}.json"
        report = json.load(open(out_json))
        total_openai_seconds += report["timing"]["totalElapsedMs"] / 1000
        translations.append({
            "direction": label,
            "source_wav": rel(src_wav),
            "source_transcript": report["inputTranscript"],
            "output_wav": rel(out_wav),
            "output_transcript_json": rel(out_json),
            "output_transcript": report["outputTranscript"],
            "output_language": target_lang,
            "latency_ms": report["timing"],
        })

    notes = []
    if story == "rome-trattoria":
        notes.append("An extra background figure resembling a second waiter appears seated at the table in the establish/local shots; not disqualifying (faces/hands/limbs are clean) but flagged for the editor to crop around if it reads as cluttered.")
    if story == "kyoto-shop":
        notes.append("Regenerated twice: v1's customer read as an ambiguous local rather than a clearly foreign tourist (QC reject on role/ethnicity clarity) -- fixed with an explicit Western-appearance description. The shopkeeper's JA line was then regenerated a third time with slow, clearly-enunciated phrasing after the first take's audio was too indistinct for gpt-4o-mini-transcribe to hear \"chiisai\" correctly (it heard \"shai\"), which silently dropped 'small' from the translation.")
    if story == "seoul-pharmacy":
        notes.append("EN->KO translation of \"Do you have something for a sore throat?\" needed 5 attempts: gpt-realtime-translate repeatedly mistranslated the concept (bronchitis, complexion, dry cough) before landing on a correct rendering. This looks like a genuine, reproducible model weakness for this phrase, not a one-off glitch -- worth flagging for the app's own translation-quality backlog. The local->EN reply also needed a retry after one run returned only 400ms of truncated output audio for a full-sentence transcript.")
    if not notes:
        notes.append("Clean on first take: all four shots and both translation directions passed QC without retries.")

    manifest["stories"].append({
        "id": story,
        "local_language": lang,
        "shots": shots,
        "translations": translations,
        "notes": notes,
    })

manifest["openai_spend_this_production_run"] = {
    "total_connected_seconds": round(total_openai_seconds, 1),
    "note": "Sum of totalElapsedMs across every translate_audio.mjs call that produced a KEPT file (14 calls: 2 directions x 7 stories). Retries that were discarded are not counted here but are listed in each story's notes: seoul-pharmacy needed 5 extra discarded calls (4 for the EN->KO mistranslation, 1 for the truncated KO->EN run), kyoto-shop needed 2 extra discarded calls (both JA->EN attempts against the garbled v1/v2 dialogue audio, before the v3 video fix). Grand total across all calls (kept + discarded) this production run is ~206s (~3.4 min) of connected session time.",
    "estimated_cost_usd": "~0.13 (206s / 60 * ($0.034/min translate + $0.003/min gpt-4o-mini-transcribe input)) for this production run; the earlier tool-build/test session (audio-tool.md) spent a separate ~0.12-0.15. Combined ~0.25-0.28, well under the $3 cap. No gpt-4o-mini-tts fallback calls were needed -- every dialogue line was eventually produced by LTX-2.5 itself.",
}

with open("/Users/marcus/Dev/ios/psybeam/marketing/video/assets/manifest.json", "w") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)

print("wrote manifest.json")
print(json.dumps(manifest["openai_spend_this_production_run"], indent=2))
