# Slopometer

**Your daily slop, quantified.**

A native Mac instrument for measuring one GitHub account's activity:
contribution grids, columns, trend lines, moving averages, and daily
pull-request quotas, on a desktop widget and in the menu bar.

Slopometer counts the activity you select. The name is a joke; the numbers
should be precise. It does not detect AI-written code, judge code quality, or
turn a PR count into a productivity score.

## Current status

MVP for testing. Slopometer runs from the menu bar (no Dock icon), syncs one
GitHub account, and shows a dashboard window and a desktop widget.

- **Username only:** the account's contribution calendar from its public profile.
- **Optional read-only tokens:** official calendar, PRs opened, authored PRs merged,
  the exact PRs behind each count, a repository filter, and a daily PR quota. Add one
  token per organization to include its private repositories.

Grid, column, and line views; 30/90/365-day ranges; 7/30-day averages. Color themes:
gradient presets (Slop Electric, GitHub, Vibe Coded, Rainbow, and more) or a custom
gradient of up to 8 colors, saved under your own names, with a System/Light/Dark switch.
Saved configurations, optional launch at login, an opt-in notification when the daily
quota is reached, and in-app updates. See the [short roadmap](ROADMAP.md).

## Uninstall

1. Open Slopometer › Settings › Uninstall › **Remove All Data…**. This deletes your tokens
   from Keychain and everything else the app saved, and lists the tokens it deleted.
2. Revoke those tokens on GitHub: [fine-grained tokens](https://github.com/settings/personal-access-tokens)
   or [classic tokens](https://github.com/settings/tokens). Deleting a token on your Mac
   does not stop it working on GitHub.
3. Quit Slopometer, move it from Applications to the Trash, and remove its widget from
   the desktop.

If the app is already in the Trash, delete the tokens by hand: in Keychain Access, search
for `vn.infinitex.slopometer.github-token` and delete each item, or run
`security delete-generic-password -s vn.infinitex.slopometer.github-token` until it reports
that the item could not be found. Then delete `~/Library/Containers/vn.infinitex.slopometer`
and `~/Library/Group Containers/5U4584QFCQ.vn.infinitex.slopometer`, and revoke the tokens
on GitHub as above.

## Develop

Requirements: macOS 14+, full Xcode 16.4+ with Swift 6.1+, Python 3.9+, and
XcodeGen **2.46.0** for project regeneration. No GitHub token is needed to build
or inspect the sample-data preview. Dependency fetching requires internet access.

```sh
make setup
make validate
make open
```

Run the `Slopometer` scheme in Xcode, or use `make run` to build a signed app and
launch it. Signing needs an Xcode account for the project team. Add the widget from
the desktop's Edit Widgets menu. `make build` (unsigned) does not launch anything. The checked-in
Xcode project can be built without XcodeGen.

The stack is Swift 6, SwiftUI, AppKit, Swift Charts, and SQLite through GRDB.
There is no application server or AI provider dependency.

## Project map

- [SPEC](SPEC.md): product behavior and measurement definitions.
- [SCOPE](SCOPE.md): the first release and explicit exclusions.
- [ROADMAP](ROADMAP.md): implementation order and completion gates.
- [Development and command registry](docs/DEVELOPMENT.md).
- [Architecture](docs/ARCHITECTURE.md) and [toolchain evidence](docs/TOOLING.md).
- [Documentation index](docs/README.md).
- [Contributing](CONTRIBUTING.md) and [agent contract](AGENTS.md).
- [Manual testing](testing/MANUAL%20TO-DO/README.md).

## License

Slopometer is free and released under the [MIT License](LICENSE). Bundled
third-party components and their licenses are listed in
[third-party notices](THIRD_PARTY_NOTICES.md).
