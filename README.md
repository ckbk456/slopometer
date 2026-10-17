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

Grid, column, and line views; 30/90/365-day ranges; 7/30-day averages. Theme
editing, saved configurations, launch at login, and notifications are planned. See
the [short roadmap](ROADMAP.md).

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

No open-source license has been selected yet. Public source availability does
not itself grant an open-source license. Licensing is a decision before a
public release or accepting external contributions.
