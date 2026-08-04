# Repository Guidelines

BabelTable is a native iOS app for real-time, two-way, face-to-face speech translation using two OpenAI realtime sessions. The shipped product name is BabelTable; do not reintroduce the older SpeakTwo repository name in source links.

## Structure

- `BabelTable/`: SwiftUI application source.
- `BabelTableTests/`: deterministic unit tests.
- `docs/`: product and App Store documentation.
- `deploy.sh`: archive and TestFlight upload workflow.

## Build and Test

```bash
xcodebuild -project BabelTable.xcodeproj -scheme BabelTable \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Voice, audio-route, interruption, and reconnection changes require real-device verification.

## Conventions

- Keep API keys in Keychain and never write audio or credentials to logs.
- Separate audio capture, realtime transport, coordination, persistence, and UI state.
- Bound reconnect backoff and prevent duplicate active sessions.
- Handle interruption, route changes, simultaneous speech, cancellation, and partial transcript ordering.
- Add user-facing strings to every supported localization.

Keep README and privacy documentation accurate. Canonical repository: `https://github.com/everettjf/babeltable`.
