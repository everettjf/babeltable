# BabelTable Privacy Policy

Last updated: May 31, 2026

BabelTable is a bring-your-own-key real-time translation app.

## Data We Collect

BabelTable does not collect, sell, or share personal data through a developer-operated server.

## OpenAI API Key

Your OpenAI API key is stored locally on your device in the iOS Keychain. BabelTable does not send your API key to any server controlled by the developer.

## Speech and Translation

When you start a translation session, audio is sent directly from the app to OpenAI's realtime translation service using the API key you provide. OpenAI processes that audio to provide transcription and translation responses.

Translation refinement is on by default and can be turned off in Settings. When it is enabled, the transcript text for each finished turn is additionally sent to OpenAI's chat completions endpoint to improve punctuation and register. That request also goes directly from your device to OpenAI using the API key you provide.

## Local Conversation History

Conversation transcripts may be saved locally on your device so you can review prior sessions. These saved sessions are not uploaded to a developer-operated server.

## Contact

For privacy questions or support, open an issue at:

https://github.com/everettjf/BabelTable/issues
