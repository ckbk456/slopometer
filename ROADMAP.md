# Slopometer roadmap

Each phase is a coherent outcome with its own validation and handoff. These are
milestones, not date estimates or authorization to publish/merge/release.

| Phase | Outcome | Exit gate | Status |
| --- | --- | --- | --- |
| 0 · Bench setup | Native fixture preview, package/cache foundation, pinned dependencies, operating docs | Local deterministic gate; manual preview explicitly pending | Locally validated; manual preview pending |
| 1 · Put the meter on the desk | AppKit desktop panel, floating toggle, menu-bar show/hide, remembered position | Named OS checks for Spaces, Show Desktop, fullscreen, monitors, sleep/wake | Planned |
| 2 · Measure real slop | GitHub auth, contribution calendar, paginated PR records, local cache and freshness | Provider reconciliation, permission failures, deduplication, timezone and rate-limit tests | Planned |
| 3 · Set the daily quota | PR goals, evidence inspector, three charts, 7/30-day averages | Same-series chart agreement; boundary, missing-data and quota tests | Planned |
| 4 · Calibrate and package | Theme editor, saved configurations, accessibility, login launch, optional notification | Consolidated manual gates and explicit license/signing/distribution decisions | Planned |

First technical priority: prove the panel lifecycle before investing in visual
polish. First data priority: agree on what counts before celebrating a quota.
Keep human/bot selections transparent and avoid inventing an AI-quality score.

Update status only with evidence. Research belongs alongside the decision it
informs; it cannot override [SPEC](SPEC.md) or [SCOPE](SCOPE.md).
