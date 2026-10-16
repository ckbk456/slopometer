# Slopometer agent contract

## Communication and authority

- Communicate in English. Give constructive critical feedback on product and engineering decisions.
- Questions, reviews, investigations, recommendations, and plans are read-only.
  In that mode do not edit files, run code/tests/builds, install dependencies,
  generate projects, change Git state, or mutate services.
- Explicit implementation requests authorize bounded local work and validation.
  Publication needs explicit publication authority; creating a public repository
  is distinct from opening a PR. Merge, release, deployment, and destructive
  actions require exact authority. Do not rename the chat without a request.
- Preserve unrelated work and secrets. Never print tokens or commit local credentials.

## Product and documentation

- Read [SPEC](SPEC.md), [SCOPE](SCOPE.md), [ROADMAP](ROADMAP.md), and the relevant
  [logic guide](docs/README.md) before behavioral changes.
- SPEC and SCOPE are protected product contracts. This bootstrap request authorizes
  their creation; later changes need explicit human direction. Surface conflicts.
- Slop is the playful name for measured activity. Never claim code-quality or
  AI-authorship detection. Label fixture data and incomplete provider coverage.
- Update owning logic documentation, roadmap status, and the relevant consolidated
  [manual guide](testing/MANUAL%20TO-DO/README.md) with implementation changes.
- Roadmap proposals and future research cannot redefine current behavior.

## Git and ownership

- `main` is the integration branch. Use `codex/<short-kebab-case-task>`.
- This is a new repository; the initial scaffold is prepared on `codex/bootstrap`.
  Its first publication establishes the remote baseline. Subsequent work must
  use an isolated task-owned worktree based on the latest verified remote `main`.
- Inspect status, remotes/sync state, worktrees, running processes, and relevant
  listeners before edits. Do not stash, reset, overwrite, or absorb unrelated work.
- One coherent concern per branch/worktree. Keep changes locally reviewable.
  A clean checkout is not proof of synchronization.
- Multi-agent work is optional only when active runtime policy permits it and
  independent scopes justify it. The primary agent owns shared contracts,
  dependency order, combined validation, and the final integration recommendation.
  Delegation must state scope, files/worktree, interfaces, checks, docs, publication
  authority, and human gates. Avoid overlapping implementation ownership; verify reports.

## Commands and process safety

- The exact [command registry](docs/DEVELOPMENT.md) records purpose, sources,
  timing, CPU cost, environment, and determinism. Read [toolchain evidence](docs/TOOLING.md).
- `make validate` is the local gate: formatting lint, structure/docs, core tests,
  then unsigned native build. CI configuration is not evidence of CI passing.
- Before CPU-intensive commands, inspect for an equivalent run in this worktree.
  Reuse/wait for it. Run one validation command at a time; no watch mode by default.
- Keep/poll the original command session. Investigate at 3 minutes for targeted
  tests, 15 minutes for a full suite/build/typecheck, and 20 minutes for E2E.
  Check PID, parent, cwd, elapsed time, CPU, memory trend, and output before retrying.
- Only terminate the exact owned process tree. Confirm it exited before retrying;
  clean up owned processes after interruption. Never use broad process kills or
  mass `rm -rf`. High CPU alone does not indicate failure.
- `project.yml` owns the generated Xcode project. Regenerate with pinned XcodeGen
  after project changes. `Package.resolved` owns the dependency pins. If Xcode
  emits a workspace lockfile, keep its pins identical; do not hand-edit pins.

## Testing and delivery

- Prefer API/CLI/source inspection. Agent-operated UI testing needs an explicit
  request. Building does not authorize interacting with unrelated apps/accounts.
- Human QA owns desktop lifecycle, actual GitHub account behavior, permissions,
  appearance/accessibility, signing, and named OS compatibility.
- PRs need purpose, scope, validation/evidence, documentation, delivery risks,
  follow-ups, and human gates. Do not invent PR numbers or claim tests not run.
- For batches: scoped concerns, dependency audit, per-concern checks, combined-tree
  validation, explicit merge authority, then a post-merge checkpoint. A checkpoint
  is not permission to merge every open PR.
- Handoff must distinguish implemented, locally validated, CI passed, manually
  verified, published, merged, and released. Report active processes and unrun gates.
