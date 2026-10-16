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

`QuotaProgress` counts today's evidence without capping it and reports `isReached`
only when coverage is complete. Contributions are never re-bucketed: the provider's
day labels are used as-is.

The snapshot builder feeds `MovingAverage` completed days only, so today has no
average. Sync and snapshot rules are in the [sync guide](sync.md).

Deterministic evidence: `Tests/SlopometerCoreTests/MovingAverageTests.swift`, `MeasurementTests.swift`.
Human/provider checklist: [measurements and sync](../../testing/MANUAL%20TO-DO/measurements-and-sync.md).
