# Development and command registry

Run commands from the repository root. Full Xcode, Swift 6.1+, macOS 14+, Python
3.9+, and Make are required. Only regeneration requires XcodeGen 2.46.0. See
[TOOLING](TOOLING.md) for exact observed versions and CI selection.

```sh
make setup
make validate
make open
```

`make setup` checks tools, regenerates the checked-in project, and fetches the
locked dependencies. It does not install system tools. The initial bootstrap
created lockfiles once with ordinary resolution; routine setup enforces them.

## Registry

Timing is an estimate and depends on cache/network. Commands run on the named
local macOS checkout; no port, server, simulator, cloud service, or credential is
needed for the current scaffold. Make serializes its targets; SwiftPM and Xcode
receive a four-job limit, while compiler-internal scheduling remains toolchain
controlled. Agents must still inspect for separately running commands.

| Purpose / exact command | Source of truth | Expected duration | CPU-intensive | Mode / environment |
| --- | --- | --- | --- | --- |
| Tool inspection: `make doctor` | `scripts/doctor.sh` | <10s | No | Read-only tool inspection; local/CI |
| Development preparation: `make setup` | `Makefile` | 10s–3m | Low | Conditional; writes project and dependency caches; network |
| Regenerate project: `make generate` | `project.yml`, `scripts/generate.sh` | <10s | No | Deterministic with XcodeGen 2.46.0; changes generated project |
| Fetch exact dependencies: `make resolve` | `Package.swift`, `Package.resolved`, `Makefile` | 5s–3m | Low | Conditional on network/cache; cannot update locked versions |
| Format check: `make lint` | `.swift-format`, `Makefile` | <10s | No | Deterministic within selected Xcode toolchain; no edits |
| Format source: `make format` | `.swift-format`, `Makefile` | <10s | No | Mutates owned Swift files; implementation mode only |
| Structural/doc checks: `make docs-check` | `scripts/check_structure.py` | <10s | No | Deterministic; reads links, configs, and lockfiles |
| Core tests: `make test` | `Package.swift`, `Tests/`, `Makefile` | 5s–3m cold | Yes | One-shot; locked dependencies; temporary test-owned SQLite only |
| Native app: `make build` | generated Xcode project, `Makefile` | 10s–5m cold | Yes | Unsigned Debug build; writes `.build/`; no launch |
| Complete local gate: `make validate` | `Makefile` | 15s–8m cold | Yes | Sequential lint, docs, tests, build; internet if caches empty |
| Open Xcode: `make open` | `Makefile` | <10s | No | Human-owned GUI action |
| Preview app: `make run` | `Makefile` | Build + launch | Yes | Human-owned app process; quit via app/menu bar |

There is no separate JS lint, typecheck, codegen service, migration CLI, dev
server, deployment command, release job, or UI test suite. Swift compilation
checks types. Database migration runs in the cache initializer; tests use
isolated databases. Those absent gates are not applicable, not passed.

## Git and generated files

`main` is the integration branch; `codex/bootstrap` prepares the initial scaffold.
Subsequent changes use `codex/<task>` in isolated worktrees from verified remote
`main`. `project.yml` owns the committed `.xcodeproj`; regenerate after changing
targets or file membership. `Package.resolved` is canonical. Xcode 27.1 did not
emit a separate workspace lockfile for this local-package layout; if another
supported Xcode emits one, the structural check verifies its pins agree.

Build output is `.build/xcode/Build/Products/Debug/Slopometer.app`. The core
package uses `.build/`; Xcode dependency clones use `.build/SourcePackages/`.
These are ignored. No global shell config or background service is needed.

## Gates and ownership

- `make validate` is the deterministic local gate. Do not run it concurrently with
  another build/test in this worktree. Investigate long runs using AGENTS thresholds.
- CI uses the same gate on `macos-15` with Xcode 16.4, locked dependencies, and
  a pinned checkout action. It uses the committed Xcode project and does not
  separately regenerate it. No signing, provider, UI, or release checks run there.
- Keep GUI and provider results in the [manual guides](../testing/MANUAL%20TO-DO/README.md).
  Tests/builds do not establish them. Do not launch the preview during read-only work.
- Public repository/branch publication, PR creation, merging, and release are
  separate authorities. This setup request authorizes a public initial repository;
  it does not request a PR, deployment, or release.
