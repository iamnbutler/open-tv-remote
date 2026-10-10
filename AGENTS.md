# AGENTS

<!-- lane:protocol -->
## Context memory

- Before editing a file, read `.lane/memory/<path>/` if it exists, or run `lane why <path>`.
- Record non-obvious findings with `lane note add <path> -a <anchor> "..."`.
- Do not edit `.lane/` by hand; landing manages it.
- Land with `lane merge`, or `lane push` where trunk is protected, then `lane prune` once it merges.
- Detailed workflow lives in `.agents/skills/lane/SKILL.md`; run `lane install skill` if it is absent.
<!-- /lane:protocol -->

## Workflow

- `main` is protected: work in a lane (`lane new <name>`), land with `lane push`, open a pull request, and let CI pass before merging.
- Commits: `type(target): description`. Targets are folder names: `app`, `ui`, `core`, `net`, `drivers`, `discovery`, `tools`, `resources`, `repo`.
- `xcodegen generate` after adding, moving or deleting a source file; the Xcode project is generated and not checked in.
- Before pushing, build both platforms the way CI does (`.github/workflows/ci.yml`).

## Rules

- Nothing may appear on a TV unless the user asked for it: `connect()` never pairs, and discovery never sends anything a TV would show.
- Never send keys, pair, or launch apps on a real TV without asking the person you're working with first. Someone may be watching it.
- No analytics, ads, accounts, third-party SDKs or servers. The app talks only to devices on the local network.

## Docs

- Keep `README.md` short: what this is, how to build it, and links to the other top-level files and the wiki.
- User help (setup and troubleshooting per TV) lives in the GitHub wiki. Contributor and policy docs are the standard top-level files (`CONTRIBUTING.md`, `SECURITY.md`, `SUPPORT.md`, `PRIVACY.md`).
- Never restate the code: no copies of ports, protocol details, key maps, file layouts or settings. Link to the source instead; copies drift.
- A rule about a specific piece of code belongs in a lane note on that code, not in a doc.
- No plans, design notes or "what we did" write-ups. Plans live in the issue or pull request; git keeps the history.
- Do not edit docs as a side effect of an unrelated task. Update a doc only when what it says has stopped being true.
