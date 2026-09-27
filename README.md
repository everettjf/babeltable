# BabelTable

Native, offline, two-way speech translation for iPhone and iPad. Requires **iOS 27** and a device that supports Apple's on-device SpeechTranscriber.

Choose the speaking language, talk, and read the translation. Speech recognition uses Apple's SpeechAnalyzer and SpeechTranscriber; text translation uses installed Apple Translation models. There is no cloud translation, account, API key, backend, subscription, or per-minute charge.

## Setup

1. Choose two different languages in Settings.
2. Tap **Download language models** while online. Allow Apple's model preparation prompts and keep the app open until **Ready for offline use** appears. Downloads require storage; availability depends on the device and language pair.
3. Tap **Start translating**, allow microphone access, and wait for **Live**.
4. Speak in the selected language. Original words appear progressively; translations follow finalized phrases. Switch the speaking language for the other person and wait for **Live** again.
5. Tap **Stop** to complete the final phrase and save the conversation to History.

After model preparation, conversations work without an internet connection, including airplane mode. If system-managed models are removed, prepare them again while online. Model downloads are the only online step in the translation workflow.

## Behavior

- Chat layout or face-to-face layout with the far panel rotated 180 degrees.
- Explicit speaking-language selection; speak one at a time. Simultaneous overlapping speech and automatic speaker identification are not supported.
- Progressive source captions, phrase-by-phrase translations, microphone level, and optional volume balancing.
- Utterance IDs keep delayed translations attached to the correct source phrase.
- Local drafts, History, deletion, and text sharing. Existing archives remain readable.
- Backgrounding or an audio interruption pauses capture and preserves visible text. Audio spoken during a pause is not recorded. Return to the app or tap Resume to continue.
- No audio recording to disk, remote transcript refinement, or spoken translation playback.

Language choices are candidates, not a promise of availability. Settings checks both speech recognition locales and both translation directions on the actual device before declaring a pair ready.

## Development

Use Xcode 27 with the iOS 27 SDK:

```bash
xcodebuild -project BabelTable.xcodeproj -scheme BabelTable \
  -destination 'platform=iOS Simulator,name=iPhone 17e' test
```

The local pipeline uses iOS 27's AnalyzerInputConverter and the new audio-session deactivation/resumption notifications. Installed-only TranslationSession instances use the low-latency strategy; runtime startup never requests model downloads or falls back to a remote service.

Deterministic tests inject audio and local engines to verify cancellation, phrase ownership, direction switching, final draining, model errors, interruption recovery, draft persistence, and save retry. Apple's actual speech/translation models and audio routes require a physical device; simulator tests do not establish translation accuracy. Physical-device integration tests require prepared English/Chinese models and verify both translation directions plus synthetic speech on first start and restart, without opening the microphone. See [release validation](docs/APP_STORE_CLOSEOUT.md).

## Privacy

Audio and translation content are processed on the device. Transcripts and usage duration are saved locally; device backups may include them. Sharing is user initiated. Apple manages model downloads and may collect framework usage/performance diagnostics. See [PRIVACY.md](PRIVACY.md).

Upgrading removes the obsolete saved credential without reading its contents. Previously saved conversations remain available.

## Deployment

`deploy.sh` archives and uploads to TestFlight. Verify the intended version/build and tests first:

```bash
source ~/.zshrc   # supplies APPLE_ID and APP_SPECIFIC_PASSWORD
./deploy.sh
```

## Contributing and license

[Repository](https://github.com/everettjf/babeltable) · [Issues](https://github.com/everettjf/babeltable/issues) · [MIT License](LICENSE)
