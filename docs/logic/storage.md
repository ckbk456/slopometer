# Storage logic: implemented foundation

Owner: `Sources/SlopometerCore/MeasurementCache.swift`.

`MeasurementCache` uses GRDB's serialized `DatabaseQueue`. The initializer opens
an in-memory database by default or a caller-provided file, then applies the
named `createDailyMeasurements` migration without erasing data.

`CachedDay` stores a series ID, already-bucketed ISO day label, and optional count.
The composite primary key is `(seriesID, day)`. Saving the same key replaces its
count rather than adding another day. Queries isolate the series and sort day
labels lexically; the caller must supply canonical YYYY-MM-DD dates. Counts may
be unknown (`NULL`) or nonnegative, with a database constraint and API validation.
Empty series IDs are rejected by the API.

The series identity must eventually encode metric, repository/author selection,
and timezone policy. This bootstrap does not yet construct those identities,
validate calendar strings, track freshness/coverage, or persist raw PR records.
The preview currently uses memory fixtures and does not open a production cache.

Future schema changes add a named migration and preserve prior user data. Do not
enable erase-on-schema-change or use this derived cache as PR quota evidence.
Credentials never belong in this database.

Deterministic evidence: `Tests/SlopometerCoreTests/MeasurementCacheTests.swift`
covers repeat writes, isolation, unknown versus zero, rejected writes, and reopen
persistence. Human/provider checklist: [measurements and sync](../../testing/MANUAL%20TO-DO/measurements-and-sync.md).
