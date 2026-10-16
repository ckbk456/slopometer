# Slopometer specification

Status: initial product contract. Features below are requirements unless
explicitly marked implemented; see [SCOPE](SCOPE.md) and [ROADMAP](ROADMAP.md).

## Purpose and voice

Slopometer is a personal, native macOS dashboard for measuring selected GitHub
activity. It is purely a slop-measuring instrument. "Slop" is playful product
language for the counted activity, not an assessment of its authorship or quality.

Use restrained instrument-like presentation with occasional labels such as
"Daily slop quota." Always expose the real unit: contributions, PRs opened, or
authored PRs merged. Avoid opaque slop scores, worker rankings, quality claims,
or fabricated AI attribution. The tagline is "Your daily slop, quantified."

## Surfaces

1. **Desktop panel:** resizable chart, metric/scope label, daily quota, freshness
   indicator, and access to controls. Intended to sit above wallpaper and behind
   ordinary windows. Optional floating mode, position lock, and remembered monitor
   placement. Desktop/Spaces behavior is an early feasibility gate.
2. **Menu bar:** show/hide the panel, refresh, switch saved configurations, open
   settings, and quit. Quitting stops this application's polling.
3. **Expanded app window:** inspect dates and the PRs behind a count, choose
   repositories/authors, and edit appearance and goals.

The current scaffold implements an ordinary app-window preview and menu-bar
entry. It does not yet implement desktop attachment or the expanded inspector.

## Measurements

| Metric | Definition | Scope and date policy |
| --- | --- | --- |
| GitHub contributions | GitHub's supplied daily contribution count | Account-wide calendar using the provider's day labels; do not silently re-bucket or pretend to filter its total by repository |
| PRs opened | Unique selected-author PRs created during the interval | Selected repositories; `createdAt` bucketed in the selected timezone; drafts included and labeled |
| Authored PRs merged | Unique selected-author PRs merged during the interval | Selected repositories; `mergedAt` bucketed in the selected timezone, regardless of who clicked Merge or when the PR opened |

Human and bot authors are explicit selections. GitHub identity is evidence of
the recorded author, not proof of who or what wrote the code. Multiple selected
authors require permission to read the relevant PRs; unsupported/inaccessible
scopes must be shown, not silently counted as zero.

Use stable GitHub PR identifiers to deduplicate. A PR opened last month and
merged today counts toward today's merged metric. Merely reopening an existing
PR is not another opening. Changes to old PRs must be reconciled by sync.

Store source timestamps in UTC. Derive PR day buckets with the selected IANA
timezone using calendar-day boundaries, including daylight-saving transitions.
The goal timezone is explicit and persists until changed; changing timezone
recomputes the series. Contribution-calendar day labels remain provider-defined.

Private PR details require authorized repository access. An anonymized private
contribution count does not provide the PR identities needed for a quota.
Display last successful sync and incomplete coverage alongside cached data.

## Charts and averages

- Grid: GitHub-style daily heatmap with count/date tooltips and accessible labels.
- Columns: daily counts, optional average overlay, zero baseline.
- Line: the same daily counts and optional average overlay. Avoid smoothing that
  suggests negative counts or activity between events.
- Views share the same selected metric, scope, and data completeness policy.
- Date ranges: 30, 90, and 365 days. Contributions may retain provider-calendar
  layout; PR series use the selected goal timezone.
- Trailing simple moving average: off, 7 days, or 30 days. Include confirmed
  zero-activity days in the denominator. Unknown days invalidate the affected
  window. Fetch pre-range history for warm-up; insufficient history has no average.
- Today is labeled incomplete. The default trend uses completed days; today's
  live count and quota remain visible separately.

## Daily PR quota

One active goal in v1: metric (`PRs opened` or `authored PRs merged`), positive
integer target, selected authors/repositories, and timezone. The suggested metric
is authored PRs merged. Goals are personal targets and never assess code quality.

Show "Daily slop quota: 3 / 5 authored PRs merged" with unit and scope. Progress
may exceed the target; do not cap the numeric count. Clicking the count reveals
the exact PRs counted. Reset at calendar midnight in the goal timezone, not by
subtracting 24 hours. Target edits apply immediately and do not alter raw events.

Keep the goal count separate when the chart displays another metric. Completion
notifications are opt-in, at most once per goal/day after confirmed data, and
cannot claim a target was reached when coverage is incomplete. No streak penalty
or guilt notification is required.

## Appearance and behavior

Provide light/dark/system appearance, palette presets and custom colors for
heatmap levels, chart marks, moving average, goal, text, and panel background.
Expose opacity and compact/comfortable density. Preserve legibility and system
accessibility preferences; color alone must not convey a count or status.

A saved panel configuration includes metric, scope, chart, range, average,
theme, density, panel placement, and goal reference. Start with one panel and
one account; multiple named configurations can reuse that panel.

## Sync and local data

Keep source records and derived measurements separate. SQLite is a local cache,
not the authoritative GitHub source. Cached days include a metric/scope/timezone
series identity. Settings and credentials have separate storage.

While running, poll on a conservative 5–15 minute schedule, refresh after wake
or foreground activation when stale, and allow manual refresh. Coalesce requests,
paginate, respect provider rate limits, and back off after errors. No per-second
networking, background daemon, or claim of instant updates is required.

Credentials belong in Keychain. Never place tokens in source, preferences,
logs, or chart exports. The sample-data scaffold needs no credentials. Dedicated
sign-in and private-repository permissions remain an implementation gate.

## Acceptance gates

- Each chart agrees on the same daily data and explains missing/stale data.
- PR quotas can be traced to stable PR IDs and reproduce their timezone boundaries.
- Pagination/repeated sync cannot double-count; delayed merges are reconciled.
- Panel behavior is checked across Spaces, Show Desktop, fullscreen, monitor
  changes, sleep/wake, and application restart on named macOS versions.
- Keyboard access, VoiceOver labels, contrast, and Reduce Motion are checked.
- No provider, manual, signing, or OS-compatibility check is inferred from a build.

Changes to this product contract require explicit human authorization.
