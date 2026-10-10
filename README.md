# Open Source TV Remote

A free TV remote for iPhone, iPad and Mac, made because the App Store is full of
"free" remote apps that quietly charge $12.99 a week. This one has no subscriptions,
ads, tracking or accounts. It talks directly to your TV over your Wi-Fi.

| TV | Protocol | Pairing |
|---|---|---|
| Google TV / Android TV (Sony, TCL, Hisense, Philips, Chromecast, Shield…) | Android TV Remote v2: mutual TLS + protobuf on 6466/6467 | 6-character code shown on TV |
| Roku | External Control Protocol, HTTP :8060 | none |
| Samsung Tizen (2016+) | WebSocket :8002 | Allow prompt on TV |
| LG webOS | SSAP WebSocket :3001 / :3000 | Accept prompt on TV |

Nothing in the app shows anything on a TV until the user taps **Pair**.

## Layout

- `Sources/Core`: device model, the `TVDriver` protocol, app catalog
- `Sources/Net`: protobuf codec, DER/X.509 builder, client identity (keychain), TLS/WebSocket/HTTP helpers
- `Sources/Drivers`: one driver per TV platform
- `Sources/Discovery`: Bonjour, SSDP and a TCP subnet sweep (the sweep exists because iOS blocks SSDP multicast without Apple's multicast entitlement)
- `Sources/UI`: SwiftUI, shared by iOS and macOS
- `Tools/harness`: command-line harness that drives the real Android TV driver (`Tools/harness/build.sh`)
- `Tools/render-icon.swift`: regenerates the app icon (`swift Tools/render-icon.swift Resources/Assets.xcassets/AppIcon.appiconset`)

## Privacy

Open Remote collects nothing. There are no analytics, no accounts and no servers;
the only network traffic is between your device and your TV.

## Build

```sh
xcodegen generate
open OpenRemote.xcodeproj
```

## Release to TestFlight

App Store Connect app ID 6821346948, bundle `com.natebutler.freeremote`, team `8S43JJMN6B`.
Build numbers are bumped automatically on upload.

```sh
cat > build/ExportOptions.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>8S43JJMN6B</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><true/>
</dict></plist>
EOF
for platform in iOS macOS; do
  xcodebuild -project OpenRemote.xcodeproj -scheme OpenRemote -destination "generic/platform=$platform" \
    -archivePath build/OpenRemote-$platform.xcarchive -allowProvisioningUpdates archive
  xcodebuild -exportArchive -archivePath build/OpenRemote-$platform.xcarchive \
    -exportOptionsPlist build/ExportOptions.plist -exportPath build/export-$platform -allowProvisioningUpdates
done
```

## License

MIT
