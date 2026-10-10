---
id: 01M4KZDJ9D1RTKC3FADYBE84ZJ
anchor: '@file'
created: 2026-10-10T22:37:27Z
norm: '1'
sig: 55aac2c2aa641984
body_hash: 58172bec5a0b12cb
raw_hash: ef56c27885b89450
lines: 1-449
supersedes: 01M4KBQXWDXYWGA57WDQ88ZNDN
---

Jellyfin for Android TV only takes remote PlayNow while it's in the foreground, but the server keeps listing its session after it's backgrounded, and re-launching the app mid-playback resets it to home. So play() finds the TV's session by RemoteEndPoint, launches only when nothing is playing, and resends PlayNow until NowPlayingItem confirms it.
