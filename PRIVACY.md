# BabelTable Privacy Policy

Last updated: September 27, 2026

## On-device speech and translation

BabelTable uses Apple's on-device speech recognition and Translation frameworks. Conversation audio and text are not sent to a developer server or a cloud translation provider. There is no account, API key, advertising SDK, tracking, or remote text refinement. Make sure everyone agrees before using the microphone.

Microphone audio is processed in memory and is not saved as recordings. Capture stops when you stop the conversation, background the app, or an interruption pauses the session. Speech during a pause is not recorded.

## Language models and Apple services

An internet connection is required to download the speech and translation models before first use, and when preparing a different pair or replacing removed models. Apple manages these downloads. Once installed, supported languages work offline. The app does not fall back to a cloud translation service.

Apple's frameworks may collect API usage and performance metrics, including app identity and language information. Apple's Translation documentation states these metrics exclude original and translated content. Apple's services and system diagnostics are governed by Apple's terms and privacy policy: [Apple Privacy Policy](https://www.apple.com/legal/privacy/) and [TranslationSession documentation](https://developer.apple.com/documentation/translation/translationsession).

## Local history and sharing

Transcripts and translations are saved in local app storage, including drafts and existing conversations from earlier versions. You can delete them in History. Device backups may include this storage depending on your system settings. The developer does not receive these archives.

Export and sharing use the system share sheet only when you request them. The destination you choose controls the shared copy; deleting an in-app conversation does not delete exported copies or backups.

## Diagnostics and usage

Conversation duration and a bounded diagnostic log are stored locally. Diagnostics do not intentionally include conversation text or audio. You can inspect, clear, or share diagnostics in Settings. Usage is duration only, with no billing or remote reporting.

## Upgrades

The offline version deletes the obsolete credential saved by earlier versions without reading its contents. Existing archives remain readable. This upgrade cannot remove content you previously shared or content processed by services used in earlier versions.

## Contact

For support or privacy questions, [open an issue](https://github.com/everettjf/babeltable/issues). Do not include private conversations or other sensitive information in a public issue.
