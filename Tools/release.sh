#!/bin/sh
# Archives the app and uploads it to App Store Connect (TestFlight) for each platform.
# Maintainer only: needs the team's signing access and an Xcode account signed in to App Store Connect.
# Usage: Tools/release.sh [iOS] [macOS]   (default: both)
set -e
cd "$(dirname "$0")/.."
xcodegen generate
stamp=$(date +%Y%m%d-%H%M%S)
platforms=${*:-iOS macOS}
for platform in $platforms; do
  archive="build/release/$stamp/OpenRemote-$platform.xcarchive"
  xcodebuild -project OpenRemote.xcodeproj -scheme OpenRemote -destination "generic/platform=$platform" \
    -archivePath "$archive" -allowProvisioningUpdates archive
  xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist Tools/ExportOptions.plist \
    -exportPath "build/release/$stamp/export-$platform" -allowProvisioningUpdates
done
