# Psybeam marketing video

## Capturing the app: DEBUG demo modes

A Debug build of Psybeam (1.1.1+) can render any conversation state on a simulator without a
network session, through the same code paths a real session uses: the talk buttons' real
active state, `render(legState:speaker:)`, `handleText`, and the 1.2 s quiescence that ends a
turn. Demo launches never persist settings, never ask for a rating, never report ad
attribution, and ignore GPS. Everything is compiled out of Release builds.

Install the stable build at `build/sim/Psybeam.app`, then launch it with `SIMCTL_CHILD_`-prefixed
variables (`simctl launch` only passes those to the app):

```bash
UDID=B63090D4-6D6F-467D-B504-672EA3E95500   # iPhone 17 Pro Max: 1320×2868 screenshots
xcrun simctl install "$UDID" build/sim/Psybeam.app
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100
SIMCTL_CHILD_PSYBEAM_DEMO=listening SIMCTL_CHILD_PSYBEAM_DEMO_PAIR=en:ja \
  xcrun simctl launch --terminate-running-process "$UDID" com.guitaripod.psybeam \
  -AppleLanguages "(en)" -AppleLocale en_US
xcrun simctl io "$UDID" screenshot listening.png
```

| Variable | Values | Effect |
| --- | --- | --- |
| `PSYBEAM_DEMO` | `listening` | You are holding your button; your line is on screen in their language, turned to face them, with your words upright underneath. |
| | `them` | They are holding theirs; their reply is on screen in your language, upright. |
| | `coach` | First-run coach: "Hold English and say something. You'll hear it in Japanese.", with your button breathing. |
| | `coach-theirs` | Second coach step after your first turn: your line faces them, "Now hold 日本語 and answer…" sits above the buttons, their button breathes. |
| | `destination` | The "Where are you headed?" picker. Picking a language plays on into the coach. |
| | `consent`, `settings` | The consent sheet or Settings over the conversation. |
| | `script` | Plays a timed conversation for screen recording (below). |
| | anything else | The idle screen. |
| `PSYBEAM_DEMO_PAIR` | `<you>:<them>`, e.g. `en:ja`, `ja:en`, `en:zh-Hant` | The language pair for every mode, Settings included. Chinese takes `zh-Hans` (default) or `zh-Hant` for the captions' script. Default: you speak the UI language (English if unsupported) and they speak English, or French when you already speak English. |
| `PSYBEAM_DEMO_COACH` | `1` | Runs the first-run coach during a `script` recording. |
| `PSYBEAM_DEMO_LEVEL` | `0`–`1` | The aurora's audio level for still modes. Defaults to 0.6 for `listening`, `them`, `consent` and `settings`, 0 otherwise; lower it for more caption contrast. |
| `PSYBEAM_DEMO_SCRIPT` | JSON array, or a path to a JSON file on the host | The `script` timeline. Omitted: a built-in 20 s, two-exchange conversation. |

Captions come from a built-in phrase table covering all 22 languages: the traveler asks for the
nearest pharmacy and whether it's open, the local answers. Line 0 and 2 are the traveler's, 1
and 3 the local's. Each is shown to its listener in their language, with the speaker's own words
on the upright source line.

### Script events

Every event has `at` (seconds after the conversation screen appears) and `event`; most take
`speaker` (`traveler` or `local`, default `traveler`).

| `event` | Fields | Does |
| --- | --- | --- |
| `hold` | `line`? | Presses the speaker's button: button lights, "Speak now" prompt in their language, LISTENING, the aurora follows a speech-like level. Each hold moves the speaker to their next phrase-table line unless `line` is given. |
| `release` | | Lets go. The turn completes 1.2 s after the caption stops changing, exactly like a live session. |
| `text` | `text`? or `line`? | Replaces the caption. |
| `append` | `text` | Appends a delta to the caption; repeat it to stream word by word. |
| `stream` | `text`? or `line`?, `duration`? | Streams the caption word by word (two or three characters at a time for Japanese, Chinese and Thai) across `duration` seconds. |
| `source` | `text`? or `line`? | Sets the upright source line: what the speaker said, in their language. |
| `stream_source` | `text`? or `line`?, `duration`? | Streams the source line. |
| `state` | `state`: `armed`, `listening`, `connecting`, `reconnecting`, `offline`, `idle` | Shows a leg state. |
| `pair` | `pair`: `<you>:<them>` | Switches languages mid-recording. |

Leave out `text` and the phrase table fills it in the right languages, so one script works for
every storefront:

```json
[
  {"at": 0.8, "speaker": "traveler", "event": "hold"},
  {"at": 1.2, "speaker": "traveler", "event": "stream_source", "duration": 1.6},
  {"at": 1.5, "speaker": "traveler", "event": "stream", "duration": 2.0},
  {"at": 3.9, "speaker": "traveler", "event": "release"},
  {"at": 6.2, "speaker": "local", "event": "hold"},
  {"at": 6.6, "speaker": "local", "event": "stream_source", "duration": 1.4},
  {"at": 6.9, "speaker": "local", "event": "stream", "duration": 1.8},
  {"at": 9.0, "speaker": "local", "event": "release"}
]
```

Record it with `xcrun simctl io "$UDID" recordVideo --codec h264 out.mov`, started just before the
`simctl launch`. The simulator has no microphone and plays no translated audio; add sound in the
edit.
