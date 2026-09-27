# Offline release validation

Updated: September 27, 2026. This replaces the previous cloud-release checklist. No TestFlight upload or App Store submission is part of this change.

## Implementation

- Minimum iOS version: 27.0 for the app and tests; build using Xcode 27.
- One on-device SpeechTranscriber/SpeechAnalyzer for the explicitly selected speaker, with iOS 27 AnalyzerInputConverter and audio deactivation/resumption notifications.
- Installed-only TranslationSession using the low-latency strategy. No network transport, API-key UI, remote refinement, account consent, or billing calculations.
- Settings prepares both speech locales and both text-translation directions. Models require an initial online download and storage. Unsupported devices/pairs are reported; conversation startup checks assets again and never initiates downloads.
- Partial captions replace earlier revisions. Final translations attach to stable utterance IDs. Stop and direction changes drain the analyzer before completion; preparation and draining have bounded waits.
- Interruption/background paths preserve visible text, cancel old callbacks, and pause the microphone. Nothing spoken during pauses is captured. Resume rebuilds the local pipeline.
- One stable archive UUID is used across drafts and the final save. Failed saves retain content and block a new conversation until retry succeeds.
- Earlier archives remain readable. A delete-only migration removes the obsolete Keychain credential without reading it.
- README, privacy policy, website copy, and the privacy manifest reflect on-device processing. English is the project's only supported UI localization.

## Automated verification

- iOS 27 simulator: lifecycle, archive compatibility, persistence failures/retry, and layout tests.
- Device-only integration test: translates English/Chinese in both directions using installed models. It skips explicitly if assets are missing and never accesses the microphone or requests model downloads.
- Physical-device test execution and exact results are recorded below after validation.

## Required physical acceptance before release

- [ ] Prepare English/Chinese from a clean installation. Check permission prompts, progress, cancellation, retry, storage failure, and both directions becoming ready.
- [ ] Enable airplane mode after preparation. Start, speak, switch languages, stop, and reopen History; verify correct source/translation and zero content network traffic.
- [ ] Repeat with another supported language pair; confirm unsupported combinations show an explanation.
- [ ] Test long sentences, short phrases, pauses, rapid direction switches, and accidental overlapping speech. The product requires one speaker at a time; it does not promise simultaneous speaker separation.
- [ ] Test phone/Siri interruptions, Bluetooth connect/disconnect, media-services reset, background/foreground, and stop during preparation/draining on real hardware.
- [ ] Test VoiceOver, large text, iPad, and face-to-face viewing. Refresh App Store screenshots for the offline version.
- [ ] Review translation quality and latency with real speakers. Simulator/mocked tests do not establish these properties.

## App Review notes

BabelTable translates speech locally using Apple's Speech and Translation frameworks. Requires iOS 27 and hardware/languages supported by SpeechTranscriber. No account, API key, subscription, or in-app purchase is required.

Open Settings, select two different languages, and tap Download language models while online. Complete Apple's model prompts and wait for Ready for offline use. Tap Start translating, grant microphone permission, and wait for Live. Speak in the selected language; original captions appear progressively and translated text follows finalized phrases. Switch the speaking language before the other person speaks. Prepared models work in airplane mode. Stop saves the conversation locally; History supports reading, deletion, and text sharing. Output is text, not spoken audio.

The bundled privacy manifest declares no developer-collected data. Confirm App Store privacy answers against the current Apple framework disclosures; model-download/API performance diagnostics are controlled by Apple. Device backups and user-requested sharing are described in the privacy policy.

## Verification results (2026-09-27)

- Xcode 27.0 (27A266a), iPhone 17e / iOS 27 simulator: **28 tests executed, 27 passed, 1 explicitly skipped, 0 failures**. The skipped test requires physical-device translation assets.
- The audio converter test exercises the real iOS 27 converter with ten PCM16 chunks plus flush, checking that one second of input remains one second after resampling. A preliminary float-output test hit the framework's PCM16 precondition; the test now uses the required format and runtime validates the model format before creating the converter.
- Exported and reviewed simulator screenshots of Settings and the large-text home screen; the layout suite renders iPhone, large-text iPhone, and iPad variants of Home, Settings, and onboarding.
- Generic iOS **Release build succeeded** with signing disabled. The physical-device Debug test build also compiled and signed successfully.
- Physical iPhone 17 Pro: the first device run completed after unlocking, with **27 tests executed, 26 passed, 1 skipped, 0 failures**. The installed-model test confirmed the English/Chinese pair is supported but reported **needsDownload**. A later run including the audio converter test was blocked by the device locking again. Actual microphone, airplane-mode translation, installed-model integration, and audio-route acceptance remain unverified. Prepare models and complete the checklist before release.
- No TestFlight upload performed.
