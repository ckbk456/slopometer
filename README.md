# Slopometer

**Your daily slop, quantified.**

A native Mac instrument for measuring GitHub activity: contribution grids,
columns, trend lines, moving averages, and daily pull-request quotas. Keep an
eye on the output of your human-and-agent software factory from the desktop.

Slopometer counts the activity you select. The name is a joke; the numbers
should be precise. It does not detect AI-written code, judge code quality, or
turn a PR count into a productivity score.

## Current status

Development scaffold, not a connected GitHub client. The native app previews
grid, column, and line charts using fixed **sample data**, with a 7-day average
on the column and line views. It has a menu-bar entry, a shared Swift package,
a migrated SQLite cache foundation, and deterministic core tests.

Desktop attachment, authentication, GitHub sync, real PR quotas, theme editing,
and saved configurations are planned. See the [short roadmap](ROADMAP.md).

## Develop

Requirements: macOS 14+, full Xcode 16.4+ with Swift 6.1+, Python 3.9+, and
XcodeGen **2.46.0** for project regeneration. No GitHub token is needed to build
or inspect the sample-data preview. Dependency fetching requires internet access.

```sh
make setup
make validate
make open
```

Run the `Slopometer` scheme in Xcode, or use `make run` to build and open the
unsigned development app. `make build` alone does not launch it. The checked-in
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
