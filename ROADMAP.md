# Slopometer roadmap

Each phase is a coherent outcome with its own validation and handoff. These are
milestones, not date estimates or authorization to publish/merge/release.

| Phase | Outcome | Exit gate | Status |
| --- | --- | --- | --- |
| 0 · Bench setup | Native fixture preview, package/cache foundation, pinned dependencies, operating docs | Local deterministic gate; manual preview explicitly pending | CI passed on `main` (run 38923006922, Xcode 16.4); manual preview pending |
| 1 · Harden the bench | Single CI run per change, project drift check, consistent formatter and signing, widget extension with App Group and shared snapshot format | CI gate; widget appears from a locally signed build (manual) | Toolchain merged (#2); widget built and signed locally; manual widget check pending |
| 2 · Measure real slop | Source records, timezone bucketing, cache v2, public-profile calendar, optional token with GraphQL calendar and PR search, recorded fixtures | Reconciliation, deduplication, removed-PR, timezone, search-window, rate-limit, and token-mismatch tests | MVP: tests pass locally; live sync exercised on one account; manual provider checks pending |
| 3 · Set the daily quota | PR goals, evidence inspector, three charts, 7/30-day averages, widget views | Same-series chart/widget agreement; boundary, missing-data and quota tests | MVP: implemented without login launch or notifications; manual checks pending |
| 4 · Calibrate and package | Theme editor, saved configurations, accessibility, login launch, optional notification | Consolidated manual gates and explicit license/signing/distribution decisions | Planned |

First technical priority: settle data contracts and widget plumbing before
visual polish. First data priority: agree on what counts before celebrating a
quota. Keep the token requirement explicit and avoid inventing an AI-quality score.

Data-source evidence behind the account-level, optional-token design is in
[GitHub data sources](docs/research/github-data-sources.md).

Update status only with evidence. Research belongs alongside the decision it
informs; it cannot override [SPEC](SPEC.md) or [SCOPE](SCOPE.md).
