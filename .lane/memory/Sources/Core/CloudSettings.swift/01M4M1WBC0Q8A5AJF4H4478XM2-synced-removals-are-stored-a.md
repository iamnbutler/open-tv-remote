---
id: 01M4M1WBC0Q8A5AJF4H4478XM2
anchor: '@file'
created: 2026-10-10T23:20:28Z
norm: '1'
sig: 55aac2c2aa641984
body_hash: 59efe54e4663c6fd
raw_hash: 4aab026946f4a87a
lines: 1-124
---

Synced removals are stored as empty Data, not removeObject, so a key nobody has written (cloud nil) can safely be filled from this device at launch, including when iCloud is signed out, without undoing a removal made elsewhere.
