# BabelTable 1.0 App Store closeout

Updated: 2026-09-22. This checklist supersedes completion percentages in the historical roadmap. Source version remains 1.0 (9); no TestFlight upload or App Store submission has been performed as part of this closeout.

## Implemented

- Saving returns success/failure. Failed final saves retain the session in memory, suppress the success notice, and block clearing/starting until retry succeeds. Text remains shareable. Deletion failures remain visible and do not remove the item from the list.
- Periodic drafts contain finalized, draining, and open turns. Background/offline transitions snapshot immediately. Final saves use the same UUID. Refinement updates a live draft immediately; stopping cancels pending refinement, preserving the final displayed text in the archive.
- Live requires both configured connections and ready microphone capture. No audio is forwarded while starting, interrupted, or reconnecting. Connection generations reject stale events after stop/rebuild. Capture generations prevent an old asynchronous start/restart from taking ownership after stop. Configuration acknowledgement has a timeout, and retries remain bounded.
- Short utterances have no four-character threshold. Both candidate outputs are retained for routing, including output received before input. Recognized language changes split rapid exchanges. Consecutive same-language turns use the actual previous output time so a later translation is not incorrectly attached to the previous turn. Reconnecting closes the previous connection's pending turns.
- Audio engine lifecycle is serialized on MainActor. Each tap owns its converter; route changes rebuild capture and media-services reset replaces the engine. User stop cancels pending recovery.
- Explicit OpenAI data-sharing consent gates realtime and refinement requests. Consent can be withdrawn in Settings, which stops capture. Privacy policy and OpenAI privacy links are available in-app.
- Onboarding can be skipped. Key deletion preserves history. Keychain writes/deletes report failure; saved keys use device-only protection. The UI distinguishes key authentication from realtime model/billing availability.
- Refinement defaults off for new installations; existing choices are preserved. Labels, refinement, glossary, audio tuning, and diagnostics live in Advanced settings. Current/visible session language labels stay tied to that session.
- Archived conversations export actual UTF-8 `.txt` files. Current caption text remains shareable without stopping.
- Server diagnostics use fixed error categories, not remote payloads or messages. Unknown event names are not logged. README and privacy policy describe optional refinement, local history/backups, estimates, and recording pauses.

## Automated evidence

- iPhone 17 / iOS 27 simulator: 54 XCTest + 1 Swift Testing tests passed on 2026-09-22 before the final lifecycle review.
- Everett iPhone 27 (iPhone 17 Pro): the same 55 tests passed on the physical device. Tests use isolated directories, defaults and test-only Keychain entries, injected transports, and injected audio. They do not prove live microphone accuracy or actual interruption recovery.
- Release simulator build passed.
- Final source verification: 57 XCTest + 1 Swift Testing tests passed on the iPhone 17 simulator; final Release simulator build passed. Result bundle: `/tmp/babeltable-turn-order.xcresult` on the verification host.
- Twelve UIKit-hosted layout attachments cover Home, Onboarding, Settings, and Privacy at iPhone/iPad point sizes plus accessibility text size. Visual review found and fixed truncated language/status controls at large text sizes. These are rendered layout checks, not a physical iPad or VoiceOver interaction pass.
- The layout test also passed on the iPad Air 11-inch (M4) simulator; Home and Privacy attachments were visually reviewed at 2048 × 2732 pixels.
- The follow-up physical-device rerun ended with a test-runner launch failure after waiting for Everett iPhone 27 to be unlocked (lost pending connection before launch). It did not verify the final source. An earlier 55-test physical-device run passed; it does not substitute for a final rerun after lifecycle and turn-order changes.
- Xcode device interaction requires first-time approval in the Xcode MCP menu. This is pending; no in-app interaction/real microphone acceptance is claimed.

The repository has no source-controlled app-test workflow. GitHub exposes a Pages deployment workflow; its result is checked after push. Local Xcode tests are the application verification gate.

## Physical speech acceptance — still required

Run the installed closeout build with your own key, model access, and available credit. Both people must agree to audio processing. Wait for Live before speaking.

- [ ] Chinese/English, at least ten turns each. Include “你好”, “谢谢”, “Hi”, rapid alternating speakers, and overlapping speech. Verify attribution, ordering and full translation in both layouts.
- [ ] Thirty-minute conversation with at least fifty turns. Verify responsiveness, the final history entry, and the exported `.txt` content. Exactly one archive per conversation.
- [ ] Background/foreground and lock/unlock. Relaunch after terminating during a draft; received text must remain available in history.
- [ ] Incoming call/Siri interruption, including an interruption during reconnection. Never show Live with a stopped microphone.
- [ ] Airplane mode/offline, Wi-Fi to cellular, and prolonged failure. No duplicate connections; visible paused/error state. Speech during pauses is intentionally not captured.
- [ ] Built-in microphone, Bluetooth connect/disconnect/reconnect, and USB-C audio if available. Verify capture resumes in the new format.
- [ ] Share to Files/Notes; compare Unicode and every completed turn. Delete history and relaunch; it must not return.
- [ ] VoiceOver reads meaningful controls in both layouts. Large text and iPad layouts remain usable, including the privacy sheet and save error actions.

Timing-based turn association cannot establish perfect attribution for simultaneously overlapping speakers. Retain this as a real-device acceptance gate rather than claiming automated proof.

## App Store Connect preparation

- Verify final version/build, distribution signing, current supported submission SDK, and App Store Connect processing status before upload.
- Use `source ~/.zshrc` and `./deploy.sh` for TestFlight. Do not print, inspect, or copy `APPLE_ID` or `APP_SPECIFIC_PASSWORD`. The script increments the build; report the actual uploaded build only after success.
- Set an accessible privacy URL and support URL. Match App Privacy answers to direct OpenAI audio/text processing and the bundled privacy manifest; do not equate “no developer backend” with “no third-party processing.”
- Refresh iPhone/iPad screenshots after final UI review. Store copy must state BYOK, separately billed OpenAI usage, internet requirement, text-only translation output, and iOS 26 minimum. Do not promise offline operation, perfect simultaneous speaker attribution, or spoken playback.
- Provide reviewers a working way to exercise realtime translation and clear setup instructions. A screenshot/demo video supplements functional access; it does not replace it. Do not commit or publicly paste a review key. Confirm the private review-access arrangement with the owner before submitting.

## Suggested review notes

BabelTable provides two-way, face-to-face speech transcription and text translation using two direct OpenAI realtime connections. It has no developer account system or developer backend. Users supply an OpenAI API key with realtime translation access and sufficient credit. The app itself has no subscription or in-app purchase.

On launch, configure the key and two different languages, or choose Set up later to inspect settings/history. Tap Start translating, review the OpenAI data-sharing notice, and agree before capture begins. Allow microphone access and wait for Live. Speak in either selected language; translations appear as text. Use Settings to switch between chat and face-to-face layouts. Stop saves one local conversation; History allows reading, deletion, and `.txt` export.

Refinement is optional and off for a new installation. If enabled in Advanced settings, it makes additional billed text requests to OpenAI. Privacy and OpenAI permission in Settings explains the data flow and allows withdrawal. Backgrounding or losing connectivity pauses capture; return to the app/network to resume.

Private review-access details: to be supplied in App Store Connect, never in this repository.
