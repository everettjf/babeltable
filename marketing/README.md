# BabelTable App Store assets

Version 1.0, build 10. English (U.S.).

- `app-store-en-US.json`: store description, promotional text, keywords, URLs and reviewer instructions. No private review contact details are stored here.
- `screenshots/`: editable Next.js project scaffolded from [ParthJadhav/app-store-screenshots](https://github.com/ParthJadhav/app-store-screenshots), retaining its device frames and PNG export pipeline. Upstream license is included.
- `exports/`: store-size PNGs exported through the editor, grouped by device, size and language.
- Source captures render the actual SwiftUI views with synthetic English/Chinese conversation data. They contain no user recordings or private history. `MarketingScreenshotTests` reproduces them as XCTest attachments.

Run the editor:

```sh
cd marketing/screenshots
npm install
npm run dev -- --hostname 127.0.0.1 --port 3047
```

Open http://127.0.0.1:3047 and use Export bundle for iPhone or iPad. Each screenshot is composed to stand on its own in App Store previews; adjacent devices must not obscure another slide's content.

Capture the source views:

```sh
xcodebuild -project BabelTable.xcodeproj -scheme BabelTable \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  -resultBundlePath /tmp/babeltable-marketing.xcresult \
  -only-testing:BabelTableTests/MarketingScreenshotTests test
xcrun xcresulttool export attachments --path /tmp/babeltable-marketing.xcresult \
  --output-path /tmp/babeltable-marketing-captures
```

These marketing captures are not evidence of real speech accuracy. Real-model English/Chinese integration was verified separately on an iPhone 17 Pro. Microphone, airplane-mode and audio-route acceptance remain manual checks.
