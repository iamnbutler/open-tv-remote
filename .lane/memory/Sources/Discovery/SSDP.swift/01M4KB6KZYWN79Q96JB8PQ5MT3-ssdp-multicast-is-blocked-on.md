---
id: 01M4KB6KZYWN79Q96JB8PQ5MT3
anchor: '@file'
created: 2026-10-10T16:44:08Z
norm: '1'
---

SSDP multicast is blocked on iOS without Apple's com.apple.developer.networking.multicast entitlement, which this app doesn't have; on iOS discovery relies on Bonjour plus the TCP subnet sweep in Discovery.swift.
