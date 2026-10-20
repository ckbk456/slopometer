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

`QuotaProgress` counts today's evidence without capping it and reports `isReached`
only when coverage is complete. Contributions are never re-bucketed: the provider's
day labels are used as-is.

`QuotaCompletion` decides the opt-in "Daily slop quota reached" notification (Settings ›
Pull requests › "Notify when reached", off by default). After each sync, one is due when
the sync verified a token and fetched PRs without error, the quota is reached with complete
coverage, and its key — the day in the goal timezone, metric, target, and repository
filter — was not announced already. Announced keys are kept in preferences for the
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
