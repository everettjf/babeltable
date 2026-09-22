# BabelTable Privacy Policy

Last updated: September 22, 2026

BabelTable is a bring-your-own-key app for live, face-to-face translation.

## Your choice

Before the first translation, BabelTable explains what is sent to OpenAI and asks for your explicit permission. Declining leaves history and settings available. You can withdraw permission in Settings → Privacy and OpenAI permission. This stops translation and prevents new translation requests until you agree again. Make sure both people agree before recording a conversation.

## OpenAI processing

During translation, microphone audio is sent directly from your device to OpenAI for transcription and translation, authenticated with your API key. Two realtime connections process the audio, one for each target language. BabelTable has no developer-operated server and does not sell your information or use advertising or tracking SDKs.

Optional translation refinement is off for new installations. If you enable it in Advanced settings, the source text, draft translation, up to three earlier conversation turns, and your glossary are sent directly to OpenAI's text API. These are separate billed requests. Existing users' refinement preferences are preserved.

OpenAI's processing and retention are governed by your OpenAI account and applicable terms. Withdrawing permission in BabelTable prevents future requests; it does not delete data already processed by OpenAI. See the [OpenAI Privacy Policy](https://openai.com/policies/privacy-policy/).

## API key

Your key is stored in the iOS Keychain and used only to authenticate requests to OpenAI. Saving a key makes an authentication request to OpenAI; this does not send conversation audio or text. Authentication does not guarantee realtime model access or available credit. You can delete the key in Settings without deleting conversation history. Newly saved keys use device-only Keychain protection.

## Local history and backups

BabelTable does not save raw microphone audio. It saves conversation transcripts and translations in its local app storage, including periodic drafts while a conversation is active. iOS device backups may include these files. The app does not operate its own cloud sync or upload history to a developer server.

History can be read, shared, and deleted in the app. Deletion removes the local conversation file; separately shared copies and older device backups are not removed by the app. Sharing creates a temporary UTF-8 text file and sends it only to the destination you select in the system share sheet.

## Diagnostics and usage

The app keeps a bounded local diagnostic log of connection states and error categories. New diagnostic entries do not include API keys, raw audio, conversation text, or complete server error payloads. You choose whether to share or clear diagnostics in Advanced settings.

Session duration and estimated usage are stored locally. These are estimates rather than OpenAI billing records; optional refinement is billed separately.

## Support

For support or privacy questions, [open an issue](https://github.com/everettjf/babeltable/issues). Do not include API keys, private conversations, or audio in a public issue.
