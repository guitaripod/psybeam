# Psybeam — social video posting kit

App Store links — use the custom product page that matches each video's destination (each shows screenshots of that language pair; until Apple approves a page, its link falls back to the default listing):

| Video | Link |
|---|---|
| tokyo-ramen, tokyo-ramen-b, kyoto-shop | https://apps.apple.com/us/app/psybeam-ai-voice-translator/id6777952645?ppid=dfcc082a-0570-4365-8b2e-9b8923027be5 |
| cdmx-tacos, cdmx-tacos-b | https://apps.apple.com/us/app/psybeam-ai-voice-translator/id6777952645?ppid=f0337398-062b-41ad-a470-86e1b1e11100 |
| paris-bakery | https://apps.apple.com/us/app/psybeam-ai-voice-translator/id6777952645?ppid=43b8aa90-7f7a-4279-ae0f-aecae2b144ca |
| rome-trattoria | https://apps.apple.com/us/app/psybeam-ai-voice-translator/id6777952645?ppid=79ce8d20-4f9d-4de3-a534-70ffbb003d82 |
| seoul-pharmacy | https://apps.apple.com/us/app/psybeam-ai-voice-translator/id6777952645?ppid=4070d967-1ce4-4bcc-ae1b-81d1a75988ef |
| bangkok-market | https://apps.apple.com/us/app/psybeam-ai-voice-translator/id6777952645?ppid=6ae7bad5-74d1-44b9-8b31-3852a93e8127 |
| kyoto-shop-ja (Japanese audience) | https://apps.apple.com/jp/app/id6777952645?ppid=3545f662-682d-436d-a771-122010cf49ff |
| generic / bio link | https://apps.apple.com/app/id6777952645 |

Every clip below is a **dramatization**: the scenes, the people and their voices are AI-generated (LTX-2.5). What is real: the phone UI is the actual Psybeam interface, screen-recorded running a scripted demo of these exact lines, and every translation you hear and read is the real output of the same gpt-realtime-translate session Psybeam uses, fed the actors' generated speech. Say this every time a platform's disclosure tooling doesn't already say it for you.

## Files

| File | Use | Dims | Length |
|---|---|---|---|
| `final/tokyo-ramen.mp4` | Social | 1080x1920 | 20.9s |
| `final/tokyo-ramen-b.mp4` | Social, hook B/A-test | 1080x1920 | 20.9s |
| `final/cdmx-tacos.mp4` | Social | 1080x1920 | 19.8s |
| `final/cdmx-tacos-b.mp4` | Social, hook B/A-test | 1080x1920 | 19.8s |
| `final/paris-bakery.mp4` | Social | 1080x1920 | 20.5s |
| `final/rome-trattoria.mp4` | Social | 1080x1920 | 20.8s |
| `final/bangkok-market.mp4` | Social | 1080x1920 | 20.8s |
| `final/seoul-pharmacy.mp4` | Social | 1080x1920 | 19.2s |
| `final/kyoto-shop.mp4` | Social, optional/secondary (see note below) | 1080x1920 | 21.1s |
| `final/kyoto-shop-ja.mp4` | Social, Japanese-audience lead cut | 1080x1920 | 21.1s |
| `final/app-preview-en-US.mp4` | App Store, en-US | 886x1920 | 15.3s |
| `final/app-preview-ja.mp4` | App Store, ja | 886x1920 | 15.3s |

The two App Previews are **App Store listing assets, not social posts** — upload them through App Store Connect metadata, not to TikTok/Reels/Shorts. They contain zero AI-generated scenes (real app UI only), so no AI-content toggle applies to them.

## AI-disclosure toggles — set this on every social upload

All 10 social clips (not the App Previews) contain AI-generated scenes and need the platform's synthetic-media disclosure turned on at upload time:

- **TikTok:** Post → Advanced settings → **"AI-generated content"** toggle → ON.
- **Instagram Reels:** Post → Advanced settings → **"AI info"** → select "AI-generated" (or the "third-party AI" option if that's what your app version shows) → ON.
- **YouTube Shorts:** Upload → "Altered content" step → answer yes to **"contains realistic altered or synthetic content"** → select the "generated with AI" reason.

Do this even though the app's own translation audio is real — the toggle covers the *scene*, and the caption/pinned comment (below) covers the rest of the honesty burden.

If the posting account's language/region is set to Japanese, the same toggles appear under their Japanese labels (TikTok: "AI生成コンテンツ"; Instagram: "AI情報" → "AI生成") — same switch, just localized; still turn it ON for `kyoto-shop-ja.mp4`.

## Pinned comment (post on every clip, right after publishing)

> Scenes, people and voices are AI-generated (a dramatization). The translations you hear and read are real, unedited output of the translation model Psybeam uses, and the phone screen is the real app.

Swap "Psybeam" wording only if a platform's character limit forces a trim; never drop the "real … unedited" clause.

For `kyoto-shop-ja.mp4`, post the Japanese pinned comment instead (its audience reads Japanese, not English):

> 映像・人物・声はAI生成の再現映像です。流れる翻訳音声と翻訳テキストは、Psybeamが使っている翻訳モデルの無編集の実際の出力で、画面は本物のアプリです。

## Per-video captions, hashtags, notes

### 1. `tokyo-ramen.mp4` — lead post
- **TikTok:** "I don't speak a word of Japanese. Watched this ramen shop understand me anyway 🍜"
- **Reels:** "POV: you walk into a Tokyo ramen shop speaking zero Japanese. Psybeam speaks it for you — for real, this is the actual translation audio."
- **Shorts:** "How I ordered ramen in Tokyo without knowing a word of Japanese"
- **Hashtags:** `#traveltok` `#japantravel` `#translatorapp` `#tokyo` `#psybeam`

### 2. `tokyo-ramen-b.mp4` — hook A/B variant of #1
- Same captions as #1; the hook line differs ("Order ramen in Tokyo. Speak zero Japanese.") so treat as a genuine variant test, not a repost — see the A/B note below.
- **Hashtags:** same as #1.

### 3. `cdmx-tacos.mp4`
- **TikTok:** "3 tacos al pastor, zero Spanish. My phone did the ordering 🌮"
- **Reels:** "I don't speak Spanish. Mexico City street tacos didn't care — Psybeam handled it, real audio."
- **Shorts:** "Ordering street tacos in Mexico City without speaking Spanish"
- **Hashtags:** `#traveltok` `#mexicocity` `#travelhack` `#spanish` `#psybeam`

### 4. `cdmx-tacos-b.mp4` — hook A/B variant of #3
- Same captions as #3; hook line differs ("Order tacos in Mexico City. Speak zero Spanish.").
- **Hashtags:** same as #3.

### 5. `paris-bakery.mp4`
- **TikTok:** "Asking for a fresh croissant in Paris without a word of French 🥐"
- **Reels:** "Zero French, one very good boulangerie. Psybeam speaks French for you — real translation audio, not a voiceover."
- **Shorts:** "How to order at a French bakery without speaking French"
- **Hashtags:** `#traveltok` `#paris` `#languagelearning` `#travelhack` `#psybeam`

### 6. `rome-trattoria.mp4`
- **TikTok:** "Ordering cacio e pepe in Rome, zero Italian required 🍝"
- **Reels:** "We don't speak Italian. The trattoria never knew — this is real Psybeam translation audio, not scripted."
- **Shorts:** "Ordering dinner in Rome without speaking Italian"
- **Hashtags:** `#traveltok` `#rometravel` `#italy` `#translatorapp` `#psybeam`

### 7. `bangkok-market.mp4`
- **TikTok:** "Pad thai, medium spicy, extra lime — ordered in Bangkok with zero Thai 🌶️"
- **Reels:** "I can't speak Thai. The night market stall never noticed. Real translation audio, every word."
- **Shorts:** "Ordering pad thai in Bangkok without speaking Thai"
- **Hashtags:** `#traveltok` `#bangkok` `#thailand` `#travelhack` `#psybeam`

### 8. `seoul-pharmacy.mp4`
- **TikTok:** "Sick in Seoul, zero Korean — my phone talked to the pharmacist for me 💊"
- **Reels:** "Sore throat, no Korean, no problem. Psybeam translated both ways — real audio, real pharmacy."
- **Shorts:** "Finding medicine in Korea without speaking Korean"
- **Hashtags:** `#traveltok` `#seoul` `#korea` `#travelhack` `#psybeam`

### 9. `kyoto-shop.mp4` — optional/secondary
- **Optional/secondary:** superseded for the Kyoto-shop scenario by `kyoto-shop-ja.mp4` (#10) below, which is the correctly-targeted cut for this footage (shopkeeper as operator, Japanese shop-staff audience). Only post this English tourist-POV cut if the account still wants a straight #1-style "traveler" entry for this destination/language — it is not required.
- **TikTok:** "Asking for a smaller size in a Kyoto shop, zero Japanese 🎎"
- **Reels:** "Shopping in Kyoto without a word of Japanese — Psybeam speaks it back and forth, for real."
- **Shorts:** "Shopping in Japan without speaking Japanese"
- **Hashtags:** `#traveltok` `#kyoto` `#japantravel` `#translatorapp` `#psybeam`
- Note: this story reuses the same en→ja direction as `tokyo-ramen` (the shop scenario, not a reversed Japanese-traveler cut) — see the "Known limitations" note in the handoff summary before treating it as a distinct language pair from #1.

### 10. `kyoto-shop-ja.mp4` — Japanese-audience post (lead cut for this scenario)
- **Different audience from #1–#9:** this cut is aimed at Japanese shop and hotel staff who serve foreign tourists, not at outbound travelers — the shopkeeper is the operator (blue/"you" = his Japanese, green/"them" = the customer's English), and every on-screen line is in Japanese. Post it from a Japanese-language account/channel (or a JP-targeted placement on the main account) rather than slotting it into the English "travel + translation demo" posting order above.
- **TikTok:** "英語が話せなくても、接客はできる。Psybeamがあれば外国人のお客様ともちゃんと話せます🎎"
- **Instagram (Reels):** "英語に自信がなくても大丈夫。Psybeamが通訳してくれるから、外国人のお客様との接客もスムーズに。実際の翻訳音声そのままです。"
- **Hashtags:** `#接客` `#インバウンド` `#外国人観光客` `#翻訳アプリ` `#Psybeam`
- **AI-disclosure toggle:** same as every other clip — turn TikTok's "AI生成コンテンツ" / Instagram's "AI情報→AI生成" toggle ON at upload (see the toggles section above).
- **Pinned comment:** use the Japanese pinned comment above, not the English one.
- Note: reuses the same two real `gpt-realtime-translate` audio pairs and LTX shots as `kyoto-shop.mp4`; only the UI capture (recorded fresh with `PSYBEAM_DEMO_PAIR=ja:en` under the Japanese locale), on-screen text, hook, and end card are new.

## Suggested post order and 14-day schedule (1/day)

Front-load the two highest-confidence concepts (food ordering, universally legible payoff, no medical/health framing risk) so the account's first 5–10 videos — the window TikTok uses to categorize the account — lock onto "travel + translation demo," then use the two hook-variant posts as genuine A/B reads before spending more production on new destinations.

| Day | Post | Why this slot |
|---|---|---|
| 1 | `tokyo-ramen.mp4` | Strongest single concept: food, universally legible, clean take with no QC flags. |
| 2 | `cdmx-tacos.mp4` | Second-strongest, different language/region, keeps the "order food abroad" template consistent for categorization. |
| 3 | `paris-bakery.mp4` | High visual appeal (croissants), still food-ordering template. |
| 4 | `seoul-pharmacy.mp4` | Introduces a relatable pain point (sick abroad) instead of food — tests whether utility framing outperforms food framing. |
| 5 | `bangkok-market.mp4` | Thai script is the hardest-to-fake language on screen — strong proof point for "20+ languages," vivid market visuals. |
| 6 | `rome-trattoria.mp4` | Romantic/couple framing, different demographic angle. |
| 7 | `kyoto-shop.mp4` (optional) | Second Japan story — deliberately last of the originals so it doesn't cannibalize Day 1's read before Day 1 has had 72h to prove out. Skip this slot (or substitute a re-cut) if it's not posted — see the optional/secondary note under #9 above. |
| 8 | `tokyo-ramen-b.mp4` | Hook A/B test against Day 1's read (same concept, different first 2s). Only post if Day 1 hit the "double-down" bar below; otherwise substitute the Day-2 hook variant or skip to Day 9. |
| 9 | `cdmx-tacos-b.mp4` | Hook A/B test against Day 2's read, same logic as Day 8. |
| 10–14 | **Reserved for rule-driven re-cuts, not pre-assigned** | By Day 10 you have 72h+ reads on Days 1–3 and 24h+ reads on Days 4–7. Apply the kill/double-down rules below to decide what fills these slots: a same-template reshoot of the winning concept in a new destination/language (Psybeam's 22-language catalog makes this near-free), not a new concept from scratch. |

`kyoto-shop-ja.mp4` (#10 above) is not part of this schedule: it targets Japanese shop/hotel staff on a Japanese-language account or placement, not the English-language "travel + translation demo" account this 14-day plan builds. Schedule it separately, on its own read/kill/double-down cadence.

## Read / kill / double-down rules

- **Read cadence:** check each post at **1h, 6h, 24h, and 72h** — cold-start accounts get a real algorithmic read fast, don't wait for 24h alone.
- **Track per post:** views, average watch/completion %, like:view ratio, comments, shares, and same-day App Store product-page views/units (no attribution SDK is wired to organic social yet, so correlate by timing).
- **Kill rule:** if a post's 24h completion rate is **<20%**, or its views are **<50% of the account's rolling median**, do not spend a second variant on that exact concept — move on, don't delete it (deleting doesn't help TikTok's per-video judging).
- **Double-down rule:** any post still gaining views after **48h**, or with completion **>40%**, gets **two immediate follow-up variants that week**: same hook/structure, new destination + language pair. This is the reusable-template advantage — one winning cut = 20+ near-free re-shoots across the other supported languages.
- Keep the account in the single "travel + translation demo" lane for at least the first 10 posts before diversifying format.

## Notes for whoever schedules these

- None of these captions claim on-device processing or that OpenAI doesn't retain audio — don't add either claim when localizing captions for other markets.
- If a post's comments ask "is this real," the pinned comment already answers it; don't argue in-thread beyond linking back to it.
