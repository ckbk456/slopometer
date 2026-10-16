# Measurement logic: implemented foundation

Owner: `Sources/SlopometerCore/MovingAverage.swift`.

`MovingAverage.trailing(_:window:)` accepts counts for consecutive calendar-day
buckets. It returns one optional Double per input day. A nonpositive window or
negative count throws. Confirmed zeros count in the denominator; an unknown
(`nil`) or insufficient warm-up makes the output `nil`. Empty input is valid.
The result includes the window ending at each supplied day.

The caller owns calendar-day continuity, timezone bucketing, fetching warm-up
history, and excluding incomplete today from the default completed-day trend.
Those date/provider rules are specified in [SPEC](../../SPEC.md) and not yet
implemented. Do not confuse this numeric function with a finished measurement engine.

The app's fixed sample series demonstrates the calculation. It is not a user's
GitHub activity. PR IDs, creation/merge timestamps, repository filters, deduplication,
and goals still need their own source records and tests before real counts ship.

Deterministic evidence: `Tests/SlopometerCoreTests/MovingAverageTests.swift`.
Human/provider checklist: [measurements and sync](../../testing/MANUAL%20TO-DO/measurements-and-sync.md).
