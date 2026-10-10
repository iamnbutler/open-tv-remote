---
id: 01M4KZDJ9D1RTKC3FADYBE84ZJ
anchor: '@file'
created: 2026-10-10T22:37:27Z
norm: '1'
supersedes: 01M4KBQXWDXYWGA57WDQ88ZNDN
---

Jellyfin for Android TV only takes remote PlayNow while it's in the foreground, but the server keeps listing its session after it's backgrounded, and re-launching the app mid-playback resets it to home. So play() finds the TV's session by RemoteEndPoint, launches only when nothing is playing, and resends PlayNow until NowPlayingItem confirms it.
