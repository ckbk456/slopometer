# Slopometer roadmap

Each phase is a coherent outcome with its own validation and handoff. These are
milestones, not date estimates or authorization to publish/merge/release.

| Phase | Outcome | Exit gate | Status |
| --- | --- | --- | --- |
| 0 · Bench setup | Native fixture preview, package/cache foundation, pinned dependencies, operating docs | Local deterministic gate; manual preview explicitly pending | CI passed on `main` (run 38923006922, Xcode 16.4); manual preview pending |
| 1 · Harden the bench | Single CI run per change, project drift check, consistent formatter and signing, widget extension with App Group and shared snapshot format | CI gate; widget appears from a locally signed build (manual) | Toolchain merged (#2); widget built and signed locally; manual widget check pending |
| 2 · Measure real slop | Source records, timezone bucketing, cache v2, public-profile calendar, optional token with GraphQL calendar and PR search, recorded fixtures | Reconciliation, deduplication, removed-PR, timezone, search-window, rate-limit, and token-mismatch tests | MVP: tests pass locally; live sync exercised on one account; manual provider checks pending |
| 3 · Set the daily quota | PR goals, evidence inspector, three charts, 7/30-day averages, widget views | Same-series chart/widget agreement; boundary, missing-data and quota tests | MVP: implemented without login launch or notifications; token gate, typed quota target, and fitted grid added; size-specific widget windows and per-size widget settings added; repository filter is a checklist of synced repositories; several tokens (one per organization) and opt-in classic tokens (InsecuSlopometer™); manual checks pending |
| 4 · Calibrate and package | Theme editor, saved configurations, accessibility, login launch, optional notification | Consolidated manual gates and explicit license/signing/distribution decisions | Planned |

First technical priority: settle data contracts and widget plumbing before
visual polish. First data priority: agree on what counts before celebrating a
quota. Keep the token requirement explicit and avoid inventing an AI-quality score.

Data-source evidence behind the account-level, optional-token design is in
[GitHub data sources](docs/research/github-data-sources.md).

Update status only with evidence. Research belongs alongside the decision it
informs; it cannot override [SPEC](SPEC.md) or [SCOPE](SCOPE.md).

Menu-bar metric icons (0.3.1): implemented with calendar, pull-request, and merge
Octicons that follow the displayed count, plus full tooltip and accessibility
wording. `make validate` passed locally on 2026-10-17 (formatting, documentation,
39 core tests, unsigned native build); project regeneration is stable with
XcodeGen 2.46.0. The user accepted the menu-bar fix on 2026-10-17; the full
appearance/accessibility matrix remains pending.

Widget sync age and tinted contrast (0.6.1): medium and large footers show the sync
clock time with an hh:mm age that advances per minute from the widget's own timeline;
busiest medium tiles cut their number out when the desktop renders the widget in one
color. Implemented with core tests for the label; desktop rendering checks are pending.

App window polish (0.7.0): implemented on `codex/app-glass-polish`. The Activity chart
fills tall windows (minimum 220 pt, scrolling when content is taller); Settings captions
are condensed to one line per tier with longer guidance behind `?` popovers; tier 3 is
headed InsecuSlopometer™ with an "Allow classic tokens" toggle; the repository picker no
longer refocuses the Username field when it closes (root cause reasoned from AppKit
focus behavior, not yet observed fixed); the app's cards, badge, and small buttons use
Liquid Glass on macOS 26+ with the earlier look as fallback. Local validation is recorded
in the handoff; every UI check in the desktop manual guide remains pending.

Menu-bar panel (0.8.0): implemented the window-style menu-bar panel with the
metric's Octicon, a large headline count or quota with the quota meter and status,
a last-7-days strip from existing snapshot series, icon-led sync/account/notice
rows, and Refresh/Open/Quit buttons with their shortcuts (Liquid Glass on macOS 26+).
Local validation and manual checks are recorded in the
[desktop guide](testing/MANUAL%20TO-DO/desktop-and-appearance.md); the panel's
appearance, keyboard, and VoiceOver behavior are not yet manually verified.

GitHub connections (0.9.0): implemented on `codex/github-connections`. With tokens, the
account is the token owner (the earliest-added verified token; others owned by someone else
are kept but not counted), so a username is needed only without tokens; SPEC was updated on
the user's direction. Fixed a stale "Verified for @x" after a username change, previous-account
PR data shown under a new account until the next sync, and refreshes dropped while a sync was
running (now queued to run right after). Settings drops the numbered tiers for an account
Username section led by the account summary, then a token list with an Add Token sheet
ending in an InsecuSlopometer™ switch row; the Activity badge names the connection and lists tokens in a
popover. Core tests cover the identity, gating, and queueing rules; every UI and provider
check in the manual guides is pending.
