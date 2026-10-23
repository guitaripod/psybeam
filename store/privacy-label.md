# Psybeam App Privacy label

Answers for App Store Connect, App Privacy section. Apple does not expose this section through the API, so the founder enters it by hand. It matches `Psybeam/PrivacyInfo.xcprivacy` and the policy at https://midgarcorp.cc/legal/psybeam/privacy (source: `web/midgarcorp/src/content/legal/psybeam/privacy.html`, last updated 23 October 2026). The Privacy Policy URL on the app info (`store/metadata/ios/app-info/*.json`, and the older copy under `marketing/appstore/metadata/app-info/`) moves from `https://mako.midgarcorp.cc/privacy/psybeam` to that address with this release; `midgar listing` pushes it and, under the `metadata_edit` policy, only with the founder at a terminal. mako redirects the old address to the new one.

This replaces whatever label the app carried before, which predates the Midgar ID. The app shipped without a privacy manifest until this release.

## Top-level answers

- Do you or your third-party partners collect data from this app: Yes.
- Data used to track you: none. No data type is used for tracking. The app asks for no tracking permission and `NSPrivacyTracking` is false with no tracking domains.
- Privacy policy URL: https://midgarcorp.cc/legal/psybeam/privacy

## Data types collected

| Data type (Apple) | Linked to the user | Used to track | Purpose | What it is in Psybeam |
| --- | --- | --- | --- | --- |
| Audio Data, Audio Data | No | No | App Functionality | The microphone audio of the conversation while a talk button is held, streamed from the phone straight to OpenAI (`gpt-realtime-translate`, with `gpt-4o-mini-transcribe` for the "what was heard" line) over WebRTC to be translated and spoken back. It does not pass through Midgar's servers, which only mint the session's short-lived token. No identifier travels with the audio; mako's session record (below) is the only link between a session and an account. Needs the person's consent (in app, before the first session). |
| Identifiers, User ID | Yes | No | App Functionality | The anonymous account key mako issues for the minutes balance, the random Midgar ID, and, if the person links Sign in with Apple, Apple's user identifier. All go to `api.midgarcorp.cc`. RevenueCat also holds its own anonymous app user id. |
| Contact Info, Email Address | Yes | No | App Functionality | Only when the person links Sign in with Apple in the credits sheet: the address Apple provides, which may be Apple's private relay address. mako stores it with the account. |
| Purchases, Purchase History | Yes | No | App Functionality | The App Store transactions of minute packs. RevenueCat verifies them and mako records them against the account. |
| Usage Data, Other Usage Data | Yes | No | Analytics | The App Store ad attribution: when the install came from an Apple ad, Apple tells mako the campaign, ad group and keyword (no advertising identifier, no device identifier). mako keeps them with the anonymous account to see which ads pay for themselves. The app sends the short-lived AdServices token for this on the first launches. |
| Usage Data, Product Interaction | No | No | Analytics | The anonymous More Apps events (opened, shown, tapped) sent by MidgarKit with no identifier. |

Everything else is "Data Not Collected".

## Data types answered "not collected", and why

- Location: the coarse position is read on the device while the app is open, only to suggest the other person's language. Apple's geocoder turns it into a country on the device's behalf; the position and the country are not sent to Midgar or OpenAI and are not stored (the country appears in the on-device log). The suggestion is optional and off with the Auto-detect switch.
- Contact Info other than the email above, Contacts, Browsing History, Search History, Sensitive Info, Financial Info, Health & Fitness, Photos or Videos: none. The camera permission text exists only because the real-time audio framework declares the capability; the app never records a photo or video.
- User Content, Other User Content: the captions of a conversation are shown on screen and kept in memory only. They are not saved and not uploaded. The audio is listed above as Audio Data.
- Identifiers, Device ID: the app reads no advertising identifier and no vendor identifier. The first mako identity is created with a DeviceCheck token that mako checks with Apple, which answers only yes or no; the app also keeps a random per-install id in the Keychain as the idempotency key. This release ships without the App Attest entitlement, so MidgarKit creates no key id yet; once it is enabled, the key id is per app and per device and is used only to prove the app is genuine when the Midgar ID is created or joined. If App Review reads either as a Device ID, the fallback is Device ID, App Functionality, linked.
- Diagnostics: the session log (`Library/Logs/psybeam.log`) stays on the device; the app has no control that shares it. MetricKit is not collected.
- Other Data: none.

## Check before the label is entered

- Audio Data is answered "not linked" because nothing but the ephemeral session token connects the stream to an account, and the token is minted by mako, not carried by the audio. mako's `realtime_sessions` row (session id, app, account, reserved and actual minutes, timestamps) is the link between a session and an account, and it holds no audio, transcript or language. If App Review or the founder reads that as "linked", switch the row to Yes; the manifest then changes to match.
- OpenAI's own retention of API audio (abuse monitoring) is governed by OpenAI's terms, which this pass did not re-read. The policy says only that OpenAI handles the audio under its own commitments.
- Other Usage Data (ad attribution) is declared because mako keeps the campaign details beside the account. Apple's AdServices guidance says attribution needs no tracking permission; the row is Analytics, not Third-Party Advertising.
- Account deletion in the app erases the mako account and everything linked to it (including the Apple identifier and email) but not the shared Midgar ID, which the other Midgar apps use; the policy says so and gives the support address.

## Third-party SDK notes

- RevenueCat (full purchase mode through AICredits, RevenueCat finishes every transaction): processes purchase data on our behalf; its manifest declares Purchase History and User ID. The Midgar ID is not sent to RevenueCat in this release (the RevenueCat app user id is unchanged), so the two identifiers are not joined by the app.
- MidgarKit: `MidgarPortal` ships a manifest that declares Product Interaction for Analytics, not linked, matching the row above.
- WebRTC (stasel/WebRTC): carries the audio to OpenAI; it collects nothing for itself.
- OpenAI: reached directly by the phone for the audio and, from mako, to mint the session token (the target language travels with that request).
- Cloudflare: hosts the gateway and the services behind it and may keep standard request logs (IP address) for a limited time; IP address is not a data type in the label.

## Required-reason APIs (in the manifest, not in the label)

- UserDefaults `CA92.1` (own settings, language pair and review state).
