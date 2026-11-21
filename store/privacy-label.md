# Psybeam App Privacy label

Answers for App Store Connect, App Privacy section. Apple does not expose this section through the API; `store/app-privacy.json` holds the same rows and is applied with `asc web privacy plan`, `apply` and `publish` (ops/runbooks/submissions-and-review.md). It matches `Resources/PrivacyInfo.xcprivacy` and the policy at https://midgarcorp.cc/legal/psybeam/privacy (source: `web/midgarcorp/src/content/legal/psybeam/privacy.html`, last updated 23 October 2026). The Privacy Policy URL on the app info (`store/metadata/ios/app-info/*.json`, and the older copy under `marketing/appstore/metadata/app-info/`) moves from `https://mako.midgarcorp.cc/privacy/psybeam` to that address with this release; `midgar listing` pushes it and, under the `metadata_edit` policy, only with the founder at a terminal. mako redirects the old address to the new one.

This replaces whatever label the app carried before, which predates the Midgar ID. The app shipped without a privacy manifest until this release.

## Top-level answers

- Do you or your third-party partners collect data from this app: Yes.
- Data used to track you: none. No data type is used for tracking. The app asks for no tracking permission and `NSPrivacyTracking` is false with no tracking domains.
- Privacy policy URL: https://midgarcorp.cc/legal/psybeam/privacy

## Data types collected

| Data type (Apple) | Linked to the user | Used to track | Purpose | What it is in Psybeam |
| --- | --- | --- | --- | --- |
| Audio Data, Audio Data | No | No | App Functionality | The microphone audio of the conversation while a talk button is held, streamed from the phone straight to OpenAI (`gpt-realtime-translate`, with `gpt-4o-mini-transcribe` for the "what was heard" line) over WebRTC to be translated and spoken back. It does not pass through Midgar's servers, which only mint the session's short-lived token. No identifier travels with the audio; mako's session record (below) is the only link between a session and an account. Needs the person's consent (in app, before the first session). |
| Identifiers, User ID | Yes | No | App Functionality | The anonymous account key mako issues for the minutes balance, the random Midgar ID, and, if the person links Sign in with Apple, Apple's user identifier. All go to `api.midgarcorp.cc`. |
| Identifiers, Device ID | Yes | No | App Functionality | The app reads no advertising identifier and no vendor identifier. The first mako identity is created with a DeviceCheck token that mako checks with Apple, which answers only yes or no; the app also keeps a random per-install id in the Keychain as the idempotency key. MidgarKit's App Attest key id, per app and per device, stored with the Midgar ID when the ID is created or joined. App Store and TestFlight builds use App Attest's production environment whether or not the app has the App Attest entitlement (Apple, App Attest Environment entitlement), so released builds create it. |
| Contact Info, Email Address | Yes | No | App Functionality | Only when the person links Sign in with Apple in the credits sheet: the address Apple provides, which may be Apple's private relay address. mako stores it with the account. |
| Purchases, Purchase History | Yes | No | App Functionality | The App Store transactions of minute packs. mako verifies each one from the signed App Store transaction and records it against the account and the Midgar ID, so the purchase history stays linked. |
| Usage Data, Other Usage Data | Yes | No | Analytics | The App Store ad attribution: when the install came from an Apple ad, Apple tells mako the campaign, ad group and keyword (no advertising identifier, no device identifier). mako keeps them with the anonymous account to see which ads pay for themselves. The app sends the short-lived AdServices token for this on the first launches. |
| Usage Data, Product Interaction | No | No | Analytics | The anonymous More Apps events (opened, shown, tapped) sent by MidgarKit with no identifier. Through the same anonymous client the app also counts which of its features are used in a week, whether the install is free, on a trial, paying or lapsed, how soon after installing its main use was first reached and which version of a screen under test was shown, and, held back for six to forty-eight hours and counted one fact at a time, what led up to a purchase or to a renewal being turned off. Each is a word from a fixed list; none carries an identifier. |
| Diagnostics, Crash Data | No | No | App Functionality | When the app crashes or freezes, MidgarKit sends one crash card to `api.midgarcorp.cc/v1/signals/diagnostics`: the kind of fault, the code addresses on the stack, the app build, the OS version and the device model, at most five a day. It holds no memory, no message text, no file path, no Midgar ID and no device identifier, and the request carries no `Authorization` header. A TestFlight or development build sends none, and turning Usage Counts off in the app's settings stops it. |
| Diagnostics, Performance Data | No | No | App Functionality | Daily numbers from MetricKit, sent as anonymous counts through the same signals client: how long the app takes to start, how long it stopped responding, the memory it used and how often the system ended it. Usage Counts turns them off too. |

Everything else is "Data Not Collected".

## Data types answered "not collected", and why

- Location: the coarse position is read on the device while the app is open, only to suggest the other person's language. Apple's geocoder turns it into a country on the device's behalf; the position and the country are not sent to Midgar or OpenAI and are not stored (the country appears in the on-device log). The suggestion is optional and off with the Auto-detect switch.
- Contact Info other than the email above, Contacts, Browsing History, Search History, Sensitive Info, Financial Info, Health & Fitness, Photos or Videos: none. The camera permission text exists only because the real-time audio framework declares the capability; the app never records a photo or video.
- User Content, Other User Content: the captions of a conversation are shown on screen and kept in memory only. They are not saved and not uploaded. The audio is listed above as Audio Data.
- Other Diagnostic Data: none. Only the crash cards and the daily performance numbers in the table leave the device; MetricKit's full reports never do. The session log (`Library/Logs/psybeam.log`) stays on the device; the app has no control that shares it.
- Other Data: none.

## Check before the label is entered

- Audio Data is answered "not linked" because nothing but the ephemeral session token connects the stream to an account, and the token is minted by mako, not carried by the audio. mako's `realtime_sessions` row (session id, app, account, reserved and actual minutes, timestamps) is the link between a session and an account, and it holds no audio, transcript or language. If App Review or the founder reads that as "linked", switch the row to Yes; the manifest then changes to match.
- OpenAI's own retention of API audio (abuse monitoring) is governed by OpenAI's terms, which this pass did not re-read. The policy says only that OpenAI handles the audio under its own commitments.
- Other Usage Data (ad attribution) is declared because mako keeps the campaign details beside the account. Apple's AdServices guidance says attribution needs no tracking permission; the row is Analytics, not Third-Party Advertising.
- Account deletion in the app erases the mako account and everything linked to it (including the Apple identifier and email) but not the shared Midgar ID, which the other Midgar apps use; the policy says so and gives the support address.

## Third-party SDK notes

- MidgarKit: `MidgarPortal` ships a manifest that declares Product Interaction for Analytics, not linked, matching the row above.
- WebRTC (stasel/WebRTC): carries the audio to OpenAI; it collects nothing for itself.
- OpenAI: reached directly by the phone for the audio and, from mako, to mint the session token (the target language travels with that request).
- Cloudflare: hosts the gateway and the services behind it and may keep standard request logs (IP address) for a limited time; IP address is not a data type in the label.

## Required-reason APIs (in the manifest, not in the label)

- UserDefaults `CA92.1` (own settings, language pair and review state).
