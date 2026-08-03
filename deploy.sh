#!/usr/bin/env bash
#
# deploy.sh — bump the build number, archive, and upload to TestFlight.
#
# Usage:
#   export APPLE_ID="you@example.com"
#   export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"   # appleid.apple.com → App-Specific Passwords
#   ./deploy.sh
#
# Optional overrides:
#   PROJECT          (default: BabelTable.xcodeproj)
#   SCHEME           (default: BabelTable)
#   CONFIGURATION    (default: Release)
#   TEAM_ID          (default: YPV49M8592)
#
set -euo pipefail

cd "$(dirname "$0")"

PROJECT="${PROJECT:-BabelTable.xcodeproj}"
SCHEME="${SCHEME:-BabelTable}"
CONFIGURATION="${CONFIGURATION:-Release}"
TEAM_ID="${TEAM_ID:-YPV49M8592}"

BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
PBXPROJ="$PROJECT/project.pbxproj"

red()    { printf "\033[31m%s\033[0m\n" "$*"; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
blue()   { printf "\033[34m%s\033[0m\n" "$*"; }

# ──────────────────────────────────────────────────────────────────────────────
# 1. Pre-flight checks.
# ──────────────────────────────────────────────────────────────────────────────
: "${APPLE_ID:?APPLE_ID is required (e.g. export APPLE_ID=\"you@example.com\")}"
: "${APP_SPECIFIC_PASSWORD:?APP_SPECIFIC_PASSWORD is required (generate at appleid.apple.com)}"

if [[ ! -d "$PROJECT" ]]; then
    red "Cannot find $PROJECT in $(pwd)"
    exit 1
fi

if ! command -v xcodebuild >/dev/null; then
    red "xcodebuild not on PATH. Install Xcode command-line tools."
    exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# 2. Bump CURRENT_PROJECT_VERSION (build number) by 1.
# ──────────────────────────────────────────────────────────────────────────────
CURRENT_BUILD=$(grep -m1 -E 'CURRENT_PROJECT_VERSION = [0-9]+;' "$PBXPROJ" | grep -oE '[0-9]+' || true)
if [[ -z "${CURRENT_BUILD:-}" ]]; then
    red "Could not locate CURRENT_PROJECT_VERSION in $PBXPROJ"
    exit 1
fi
NEW_BUILD=$((CURRENT_BUILD + 1))
blue "▶ Bumping build number: $CURRENT_BUILD → $NEW_BUILD"
# macOS sed: empty extension means in-place, no backup file.
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"

MARKETING_VERSION=$(grep -m1 -E 'MARKETING_VERSION = [^;]+;' "$PBXPROJ" | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' | tr -d ' ')
blue "▶ Version $MARKETING_VERSION ($NEW_BUILD)"

# ──────────────────────────────────────────────────────────────────────────────
# 3. Clean build directory and archive.
# ──────────────────────────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

blue "▶ Archiving $SCHEME ($CONFIGURATION)…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive | xcbeautify 2>/dev/null || \
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive

# ──────────────────────────────────────────────────────────────────────────────
# 4. Export an IPA suitable for App Store Connect.
# ──────────────────────────────────────────────────────────────────────────────
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>destination</key><string>export</string>
    <key>uploadSymbols</key><true/>
    <key>stripSwiftSymbols</key><true/>
</dict>
</plist>
PLIST

blue "▶ Exporting IPA…"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates

IPA=$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' -print -quit)
if [[ -z "$IPA" || ! -f "$IPA" ]]; then
    red "Export did not produce an .ipa under $EXPORT_DIR"
    exit 1
fi
blue "▶ IPA: $IPA"

# ──────────────────────────────────────────────────────────────────────────────
# 5. Upload to App Store Connect (becomes a TestFlight build after processing).
# ──────────────────────────────────────────────────────────────────────────────
blue "▶ Uploading to App Store Connect…"
xcrun altool --upload-app \
    --file "$IPA" \
    --type ios \
    --username "$APPLE_ID" \
    --password "$APP_SPECIFIC_PASSWORD"

green "✅ Uploaded $MARKETING_VERSION ($NEW_BUILD). Check App Store Connect → TestFlight in a few minutes for processing status."

# ──────────────────────────────────────────────────────────────────────────────
# 6. Auto-commit the build-number bump.
# ──────────────────────────────────────────────────────────────────────────────
if command -v git >/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
    if ! git diff --quiet -- "$PBXPROJ"; then
        blue "▶ Committing build bump…"
        git add "$PBXPROJ"
        git commit -m "Bump build to $NEW_BUILD"
        green "✅ Committed build $NEW_BUILD."
    else
        blue "▶ No pbxproj changes to commit."
    fi
else
    echo "Tip: not a git repo; skipping auto-commit of $PBXPROJ."
fi
