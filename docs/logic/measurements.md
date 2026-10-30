# Measurement logic: implemented foundation

Owner: `Sources/SlopometerCore/MovingAverage.swift`.

`MovingAverage.trailing(_:window:)` accepts counts for consecutive calendar-day
buckets. It returns one optional Double per input day. A nonpositive window or
negative count throws. Confirmed zeros count in the denominator; an unknown
(`nil`) or insufficient warm-up makes the output `nil`. Empty input is valid.
The result includes the window ending at each supplied day.

`CalendarDay` names a date without a timezone; `containing(_:in:)` buckets an
instant by calendar boundaries in an IANA timezone, including daylight-saving days.

`PullRequestScope` counts unique PRs (by node ID) for `PRs opened` (`createdAt`) or
`authored PRs merged` (`mergedAt`), optionally filtered to `owner/name` repositories
(case-insensitive). Days starting before the fetched coverage are unknown; covered
days with no PRs are zero. `evidence(on:in:)` returns the exact PRs behind a day.

`RepositoryFilter` drives the settings checklist. Choices are repositories with synced
PRs (merged case-insensitively, busiest first) plus selected repositories that have
none. An empty selection means all readable repositories, so every choice shows as
ticked. Unticking one from "all" keeps the rest; ticking every choice collapses back
to "all" so new repositories are included; the last ticked repository stays ticked.

`QuotaProgress` counts today's PR evidence or a known contribution-calendar total
without capping it, and reports `isReached` only when coverage is complete. Contributions are never re-bucketed: the provider's
day labels are used as-is.

`QuotaCompletion` decides the opt-in "Daily slop quota reached" notification (Settings ›
Daily goal › "Notify when reached", off by default). After each sync, one is due when
`SyncReport.confirms` establishes a successful fetch of the goal metric (calendar
replacement for contributions; verified, complete PR sync for PR goals), the quota
is reached with complete coverage, and its key — day, metric, target, and PR repository
filter — was not announced already. Contribution notification keys ignore repositories. Announced keys are kept in preferences for the
current day only, so restarts do not repeat it, while a changed goal or the next day can
be announced again. Clicking the notification opens the app window. Editing the target
alone posts nothing until the next sync confirms the count.

The Daily target field accepts digits only (`Goal.targetDigits`, at most three): anything
else typed or pasted is dropped as it arrives. Digits apply immediately, clamped into
1–999 (`Goal.target(typed:)`); leaving the field, or pressing Return, shows the current
target. It is an AppKit field whose formatter rejects non-digits as they arrive: a
SwiftUI `TextField` filtered through its binding kept showing typed letters (1.0.2). The
field takes focus only from a click inside it, Tab, or an assistive technology: when a
popover closed, focus was otherwise restored to it and the form scrolled back to it.

The snapshot builder feeds `MovingAverage` completed days only, so today has no
average. Sync and snapshot rules are in the [sync guide](sync.md).

Deterministic evidence: `Tests/SlopometerCoreTests/MovingAverageTests.swift`, `MeasurementTests.swift`.
Human/provider checklist: [measurements and sync](../../testing/MANUAL%20TO-DO/measurements-and-sync.md).

## Daily achievements (1.1.0 development)

The app remembers each observed day's quota in `quota_days`, scoped to account,
metric, repository filter (normalized and sorted), and timezone for PR goals.
Contribution history is scoped to account, metric, and calendar source instead:
provider dates are not re-bucketed and repository filters do not apply. Before a win,
today's target follows edits immediately. Once confirmed data for that metric reaches
that target, its target and achieved count are kept permanently for that day.
Raising the quota later does not erase the win; the live count and current target
still update normally. A later sync can confirm an observed prior day against its
saved target, including delayed GitHub indexing. Count corrections do not retract
an earned achievement; its label describes the count at confirmation.

No historic targets are inferred from today's setting. Tracking starts when a
quota is observed by this version; days never observed with a quota remain
unmarked. PR wins require a successful verified PR sync, complete coverage, and
coverage starting no later than that day's local midnight. Contribution wins require
a successful calendar replacement and a known count for the recorded date. Missing
dates never become zeros or wins. Startup, progressive results, failed syncs, and
settings edits alone cannot award a win. A failure of the unrelated metric does not
block a successfully confirmed goal. The current timezone selects today's date label;
contribution history retains GitHub's dates across timezone changes. Switching between
public and API calendars shows only that source's wins, preserving the other history.

The snapshot carries optional achievements on each chart point and on today's
quota. Older snapshots decode without them. Menu tiles, widget tiles, heatmaps,
and column/line charts show checkmarks. Today's menu panel, quota card, and quota
widgets gain a system-colored border and an earned-target label. An optional
per-appearance theme color customizes achievement borders and badges. Tooltips and VoiceOver
name the original target. No animation is required; the widget stops showing the
outer celebration after midnight in the achievement's timezone.

Core regression checks live in `QuotaCompletionTests.swift`. Native rendering,
widget placement, and VoiceOver remain human checks.
