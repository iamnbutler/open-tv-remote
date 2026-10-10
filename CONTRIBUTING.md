# Contributing

Thanks for helping. Bug reports, TV compatibility reports and pull requests are all welcome.

## Reporting problems

Use the [issue forms](https://github.com/iamnbutler/open-tv-remote/issues/new/choose). The brand and model of the TV matter more than anything else, because each TV family speaks a different protocol.

"Works on my TV" reports are useful too. Several TV families have only been tested on a few models.

## Pull requests

1. Open an issue first for anything bigger than a small fix, so we can agree on the approach before you spend time on it.
2. Fork the repo and branch from `main`.
3. Run `xcodegen generate` whenever you add, move or delete a source file. The Xcode project is generated, not checked in.
4. Make sure the iOS and macOS builds both pass, the same way [CI](.github/workflows/ci.yml) builds them.
5. In the pull request, say which TVs you tested on. If you couldn't test on real hardware, say that too.

`main` is protected. Every change goes through a pull request and needs passing CI before it merges.

Commit messages look like `type(target): description`, where the target is the top-level folder you changed (`ui`, `drivers`, `net`, …), for example `fix(drivers): reconnect Roku after sleep`.

## Ground rules

These aren't up for negotiation, because they're the reason the app exists:

- **No tracking.** No analytics, ads, accounts, third-party SDKs or servers. The app only talks to devices on your local network.
- **No paywalls.** Every feature is free.
- **Nothing on the TV unless the user asks.** Connecting, discovery and background work must never pop anything up on a TV. Only an explicit action, like tapping Pair, may.

## Adding a TV platform

Each TV family is one driver behind a shared protocol. Read [`TVDriver.swift`](Sources/Core/TVDriver.swift) and an existing driver in [`Sources/Drivers`](Sources/Drivers) before starting. Then add discovery for it in [`Sources/Discovery`](Sources/Discovery).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
