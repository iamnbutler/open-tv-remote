---
id: 01M4KB6KZYWN79Q96JB8PQ5MT3
anchor: '@file'
created: 2026-10-10T16:44:08Z
norm: '1'
sig: 55aac2c2aa641984
body_hash: 58a1c4af22d61617
raw_hash: 4d2f795c6844177d
lines: 1-67
---

SSDP multicast is blocked on iOS without Apple's com.apple.developer.networking.multicast entitlement, which this app doesn't have; on iOS discovery relies on Bonjour plus the TCP subnet sweep in Discovery.swift.
