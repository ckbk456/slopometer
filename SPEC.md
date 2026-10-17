# Slopometer specification

Status: product contract, revised 2026-10-16 to account-level measurement, an
optional token, and a desktop widget. Features below are requirements unless
explicitly marked implemented; see [SCOPE](SCOPE.md) and [ROADMAP](ROADMAP.md).

## Purpose and voice

Slopometer is a personal, native macOS dashboard for measuring one GitHub
account's activity. It is purely a slop-measuring instrument. "Slop" is playful
product language for the counted activity, not an assessment of its authorship
or quality.

Use restrained instrument-like presentation with occasional labels such as
"Daily slop quota." Always expose the real unit: contributions, PRs opened, or
authored PRs merged. Avoid opaque slop scores, worker rankings, quality claims,
or fabricated AI attribution. The tagline is "Your daily slop, quantified."

## Surfaces

1. **Background menu-bar app:** runs without a Dock icon, owns polling, and offers
   today's headline count, refresh, switching saved configurations, opening the
   app window, and quit. Quitting stops this application's polling.
2. **Desktop widget (WidgetKit):** the at-a-glance surface on the desktop or in
   Notification Center, in the system widget sizes. It shows chart, metric/scope
   label, quota, and freshness from the latest shared snapshot. It never fetches
   or reads credentials. Clicking it opens the app window.
3. **App window:** inspect dates and the PRs behind a count, enter the account and
   optional token, set goals, and edit appearance.

The MVP implements all three surfaces with the behavior described in the
[sync logic guide](docs/logic/sync.md); manual verification is pending.

## Account and data access

One GitHub account, identified by username. Measurement is account-level by
default. Two access tiers exist, and the app states which features need a token
before asking for one:

| Tier | Requires | Provides |
| --- | --- | --- |
| Username only | Public profile | Account contribution calendar |
| Token | One or more user-pasted read-only GitHub tokens | Official contribution calendar, PRs opened, authored PRs merged, PR evidence, PR quotas, optional repository filters |

- **Username only** reads GitHub's public profile contribution calendar. It is
  not a documented API and may change or break; label it as an unofficial source.
  Private activity appears only as anonymous counts, and only if the account
  shows private contributions on its profile.
- **Token** reads GitHub's GraphQL contribution calendar and PR search. The token
  owner must match the configured username; show a mismatch rather than counting.
  PR metrics cover only repositories the token can read. Recommend a fine-grained
  read-only token (metadata and pull requests); never require write access.
  There is no OAuth sign-in flow.
- A fine-grained token reads one resource owner's repositories, so several tokens
  may be saved (for example one for the account and one per organization). Each
  is verified separately; PRs from every verified token are merged by node ID. A
  token that fails is reported by name and marks PR coverage incomplete. Say
  plainly that an account-owned token cannot see an organization's private repositories.
- Classic tokens cannot be limited to read-only. They are refused unless the person
  opts in to **InsecuSlopometer™**, which explains that the `repo` scope grants
  write access. Classic tokens are labeled as such while saved.
- Removing the token returns to the username-only tier and hides PR data that
  can no longer be refreshed rather than presenting it as current.

## Measurements

| Metric | Definition | Scope and date policy |
| --- | --- | --- |
| GitHub contributions | GitHub's supplied daily contribution count | Account-wide; provider day labels; never filtered by repository |
| PRs opened (token) | Unique PRs authored by the account and created during the interval | All readable repositories, or a selected repository filter; `createdAt` bucketed in the selected timezone; drafts included and labeled |
| Authored PRs merged (token) | Unique PRs authored by the account and merged during the interval | All readable repositories, or a selected repository filter; `mergedAt` bucketed in the selected timezone, regardless of who clicked Merge or when the PR opened |

GitHub identity is evidence of the recorded author, not proof of who or what
wrote the code. Inaccessible or failed scopes must be shown, not silently counted
as zero.

The two contribution-calendar sources may label the same activity on adjacent
days. A contribution series has one source; switching source replaces the series
rather than mixing days from both.

Use stable GitHub PR identifiers to deduplicate. A PR opened last month and
merged today counts toward today's merged metric. Merely reopening an existing
PR is not another opening. Changes to old PRs, including deletion or loss of
access, must be reconciled by sync, so historical counts may decrease.

Store source timestamps in UTC. Derive PR day buckets with the selected IANA
timezone using calendar-day boundaries, including daylight-saving transitions.
The goal timezone is explicit and persists until changed; changing timezone
recomputes the series. Contribution-calendar day labels remain provider-defined.

Display last successful sync and incomplete coverage alongside cached data.

## Charts and averages

- Grid: GitHub-style daily heatmap with count/date tooltips and accessible labels.
- Columns: daily counts, optional average overlay, zero baseline.
- Line: the same daily counts and optional average overlay. Avoid smoothing that
  suggests negative counts or activity between events.
- Views share the same selected metric, scope, and data completeness policy.
  Each widget size shows a fixed window suited to its shape and labels it: small
  shows today's count or quota only; medium shows the last 7 days as daily tiles,
  whatever the selected view; large shows the last 26 weeks for the grid and up to
  90 days of the selected range for columns and line. Widgets omit the moving
  average, which stays in the app window.
- Date ranges: 30, 90, and 365 days. Contributions may retain provider-calendar
  layout; PR series use the selected goal timezone.
- Trailing simple moving average: off, 7 days, or 30 days. Include confirmed
  zero-activity days in the denominator. Unknown days invalidate the affected
  window. Fetch pre-range history for warm-up; insufficient history has no average.
- Today is labeled incomplete. The default trend uses completed days; today's
  live count and quota remain visible separately.

## Daily PR quota

Requires a token. One active goal in v1: metric (`PRs opened` or `authored PRs
merged`), positive integer target, scope (all readable repositories or a
selected repository filter), and timezone. The suggested metric is authored PRs
merged. Goals are personal targets and never assess code quality.

Show "Daily slop quota: 3 / 5 authored PRs merged" with unit and scope. Progress
may exceed the target; do not cap the numeric count. Clicking the count in the
app window reveals the exact PRs counted. Reset at calendar midnight in the goal
timezone, not by subtracting 24 hours. Target edits apply immediately and do not
alter raw events.

Keep the goal count separate when the chart displays another metric. Completion
notifications are opt-in, at most once per goal/day after confirmed data, and
cannot claim a target was reached when coverage is incomplete. No streak penalty
or guilt notification is required.

## Appearance and behavior

Provide light/dark/system appearance, palette presets and custom colors for
heatmap levels, chart marks, moving average, goal, text, and background. Expose
compact/comfortable density. Preserve legibility and system accessibility
preferences; color alone must not convey a count or status.

A saved configuration includes metric, scope, chart, range, average, theme,
density, and goal reference. The widget displays a chosen saved configuration.
Start with one account; multiple named configurations can share it.

## Sync and local data

Keep source records and derived measurements separate. SQLite is a local cache,
not the authoritative GitHub source. Cached days include a
metric/source/scope/timezone series identity. Settings and credentials have
separate storage.

While running, poll on a conservative 5–15 minute schedule, refresh after wake
or when stale, and allow manual refresh. Coalesce requests, paginate, split
searches into date windows below provider result caps, respect provider rate
limits, and back off after errors. No per-second networking, separate daemon,
or claim of instant updates is required.

The app publishes a small display snapshot to a shared App Group container and
requests a widget reload only when the snapshot changes. The snapshot carries
counts, labels, and freshness, never credentials. When the app is not running,
the widget shows the last snapshot with its age.

Tokens belong in Keychain. Never place tokens in source, preferences, logs,
the shared snapshot, or chart exports. The sample-data scaffold needs no
credentials.

## Acceptance gates

- Each chart and the widget agree on the same daily data and explain missing or
  stale data.
- PR quotas can be traced to stable PR IDs and reproduce their timezone boundaries.
- Pagination/repeated sync cannot double-count; delayed merges and removed PRs
  are reconciled.
- Username-only and token tiers each label their source and the features they lack.
- Widget behavior is checked across desktop and Notification Center placement,
  Spaces, multiple displays, sleep/wake, app quit, and restart on named macOS versions.
- Keyboard access, VoiceOver labels, contrast, and Reduce Motion are checked.
- No provider, manual, signing, or OS-compatibility check is inferred from a build.

Changes to this product contract require explicit human authorization.
