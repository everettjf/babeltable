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

## TestFlight Release

- Use `deploy.sh` for TestFlight uploads.
- Before running the release workflow, load the local shell configuration with `source ~/.zshrc`; it provides `APPLE_ID` and `APP_SPECIFIC_PASSWORD` for `deploy.sh`.
- Never print, inspect, copy, commit, or otherwise expose either credential. Refer only to the environment variable names in commands, documentation, and logs.
- Verify the intended version/build and the relevant tests before uploading. Treat a TestFlight upload as an external release action and report the uploaded version and build number.

## Git Workflow

- After completing each requested repository change, run the relevant verification, review `git diff` and `git status`, create a focused commit, and push it to the current upstream branch.
- Include only files belonging to the current task. Preserve unrelated user changes and never discard or overwrite them.
- Do not leave completed work uncommitted or only local unless the user explicitly asks not to commit or push, or push is genuinely blocked. If blocked, report the exact reason and retain the local commit.
- Never commit secrets, build products, Derived Data, archives, exported IPAs, or credential-bearing logs.

## Conventions

- Keep API keys in Keychain and never write audio or credentials to logs.
- Separate audio capture, realtime transport, coordination, persistence, and UI state.
- Bound reconnect backoff and prevent duplicate active sessions.
- Handle interruption, route changes, simultaneous speech, cancellation, and partial transcript ordering.
- Add user-facing strings to every supported localization.

Keep README and privacy documentation accurate. Canonical repository: `https://github.com/everettjf/babeltable`.
