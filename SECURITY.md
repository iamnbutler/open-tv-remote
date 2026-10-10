# Security policy

Please don't report security problems in public issues.

Report them privately through [GitHub's vulnerability reporting](https://github.com/iamnbutler/open-tv-remote/security/advisories/new) instead. Say what's affected, how to reproduce it, and what an attacker could do with it.

Expect a reply within a week. Fixes ship in the next App Store release, and the advisory is published once that release is out.

## Scope

The app pairs with TVs and holds their credentials, so the most important areas are:

- how pairing credentials and keys are stored on the device
- anything that lets another device on the network control a TV without the user's approval
- anything that makes the app contact something other than the TVs on the local network

Problems in the TVs' own protocols belong with the TV makers.
