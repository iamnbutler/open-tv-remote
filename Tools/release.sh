#!/bin/sh
# Archives the app and uploads it to App Store Connect (TestFlight) for each platform.
# CI runs this from .github/workflows/release.yml. Locally it uses the Xcode account you're
# signed in to; set ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID to use an API key instead.
# Usage: Tools/release.sh [iOS] [macOS]   (default: both)
set -e
cd "$(dirname "$0")/.."
xcodegen generate
stamp=$(date +%Y%m%d-%H%M%S)
platforms=${*:-iOS macOS}
set -- -allowProvisioningUpdates
if [ -n "$ASC_KEY_PATH" ]; then
  set -- "$@" -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
fi
for platform in $platforms; do
  archive="build/release/$stamp/OpenRemote-$platform.xcarchive"
  xcodebuild -project OpenRemote.xcodeproj -scheme OpenRemote -destination "generic/platform=$platform" \
    -archivePath "$archive" "$@" archive
  xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist Tools/ExportOptions.plist \
    -exportPath "build/release/$stamp/export-$platform" "$@"
done
