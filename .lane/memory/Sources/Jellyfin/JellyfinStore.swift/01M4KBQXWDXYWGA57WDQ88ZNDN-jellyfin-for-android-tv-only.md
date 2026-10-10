---
id: 01M4KBQXWDXYWGA57WDQ88ZNDN
anchor: '@file'
created: 2026-10-10T16:53:35Z
norm: '1'
sig: 55aac2c2aa641984
body_hash: 43de445b10b05cd5
raw_hash: 9bea08c6e12098a9
lines: 1-304
---

Jellyfin for Android TV only accepts remote PlayNow while the app is already running (it must have registered a session), and ignores 'navigate to item' (DisplayContent) commands, so play() launches the app through the TV driver and waits for its session first.
