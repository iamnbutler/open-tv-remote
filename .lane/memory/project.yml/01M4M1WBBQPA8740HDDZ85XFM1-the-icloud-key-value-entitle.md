---
id: 01M4M1WBBQPA8740HDDZ85XFM1
anchor: '@file'
created: 2026-10-10T23:20:28Z
norm: '1'
sig: a6656b72439eb8dc
body_hash: 5b8d3cf58070008f
raw_hash: 5d63cf687842a5d1
lines: 1-52
---

The iCloud key-value entitlement needs a provisioning profile, so a signed Mac debug build only launches on Macs registered to the team (spawn fails with POSIX 163 otherwise); xcodebuild won't register a Mac. To run locally without registering, override CODE_SIGN_ENTITLEMENTS with a copy minus com.apple.developer.ubiquity-kvstore-identifier; sync is then off.
