# App Store submission preparation — 2026-09-27

App: BabelTable (`com.xnu.babeltable`), App Store Connect ID `6807469213`.

## Completed

- Uploaded version **1.0 (10)** with `deploy.sh`; archive/export/upload succeeded. Build 10 processed and is selected on the version page.
- English (U.S.) promotional text, description, keywords, support URL, marketing URL and copyright were saved. Canonical draft: `marketing/app-store-en-US.json`.
- Subtitle: **Offline voice translation**. Primary category: Travel. Secondary: Utilities.
- Age questionnaire completed: **4+**. Not designated Made for Kids.
- Content rights: no third-party content; saved.
- Privacy policy URL: https://xnu.app/babeltable/privacy.html. Data collection answer: no data collected. Publishing the privacy responses awaits the user's confirmation of Apple's accuracy/compliance/update declaration.
- Configured a $0.00 base price and equivalent free prices across currencies.
- Uploaded **5 iPhone 6.5-inch screenshots (1284×2778)** and **5 iPad 13-inch screenshots (2064×2752)**. Both sets persist on a fresh version page.
- Used the requested ParthJadhav/app-store-screenshots template and its actual browser Export bundle workflow. Source revision: `7faf7fcd62238df12c1d7f0578191bcc73cff07c` (MIT). Editor project and exports are in `marketing/`.
- New marketing capture harness renders real app views with synthetic sample conversation data, without recording audio or modifying shipped app behavior.
- Verification: **35 simulator tests executed; 33 passed, 2 physical-device tests skipped, 0 failures**. Screenshot editor production build passed. PNG dimensions and contact sheets reviewed. The exporter reported image-load warnings for dark iPad slides and the face-to-face iPhone slide; a repeat export and visual inspection show the actual screenshot content present. It is not a clean warning-free export.

## Pending / blocked

- Review contact first name, last name, phone and email are blank. User was asked to provide these or authorize reuse from a specific existing app. Never invent contact details or commit private contact information.
- The final reviewer-note cleanup in `marketing/app-store-en-US.json` is entered in the working version form but does not persist while the required contact fields are blank. After filling contact details, replace Notes with that canonical draft and save.
- Privacy responses are ready but not published: the final Apple prompt includes a compliance/accuracy/update commitment, for which confirmation was requested.
- Worldwide availability confirmation was rejected by automatic approval review because all 175 current and future regions had not been explicitly authorized. No workaround was attempted. User was asked to choose the release scope; availability remains unset.
- Clicking **Add for Review** returned **Unable to Add for Review**, citing unpublished privacy responses and the four missing contact fields. **Nothing has been submitted for review or released.**
- Existing default Apple silicon Mac and Vision Pro availability settings were not certified as tested. Physical microphone, airplane-mode and route/interruption acceptance remain unverified as documented in APP_STORE_CLOSEOUT.md.

## Continue

1. Obtain the review contact, privacy-declaration confirmation and country/region scope.
2. Save the canonical reviewer notes with the contact details, publish the privacy responses, and set authorized availability.
3. Recheck version 1.0 build 10 and both screenshot sets. Add for Review, then submit when Apple's validation permits it.
