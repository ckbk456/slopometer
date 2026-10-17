# Storage logic: implemented foundation

Owner: `Sources/SlopometerCore/MeasurementCache.swift`.

`MeasurementCache` uses GRDB's serialized `DatabaseQueue`. The initializer opens
an in-memory database by default or a caller-provided file, then applies the
named migrations `createDailyMeasurements` and `createSourceRecords` without
erasing data. The app stores it at `Application Support/Slopometer/cache.sqlite`
inside its sandbox container.

`createSourceRecords` adds `pull_requests` (keyed by GitHub node ID, UTC
timestamps), `contribution_days` (one calendar; replacing it drops the previous
source), and a single-row `sync_state` JSON document (login, calendar source,
last successful syncs, PR coverage start, incomplete flag, last full PR sync, and
per-token PR checkpoints). `SyncState` decodes fields missing from an older
document as their defaults, so no migration was needed to add the checkpoint fields.

`replacePullRequests` is a whole-set transaction: it deletes every record, inserts
the fetch, sets coverage, the incomplete flag, the full-sync time, and the given
checkpoints. `upsertPullRequests` inserts or updates by node ID and keeps the rest;
coverage can only widen, an incomplete flag only clears with a replacement, and only
the given tokens' checkpoints change. `reset(for:)` clears data when the account changes.

`CachedDay` stores a series ID, already-bucketed ISO day label, and optional count.
The composite primary key is `(seriesID, day)`. Saving the same key replaces its
count rather than adding another day. Queries isolate the series and sort day
labels lexically; the caller must supply canonical YYYY-MM-DD dates. Counts may
be unknown (`NULL`) or nonnegative, with a database constraint and API validation.
Empty series IDs are rejected by the API.

The derived `daily_measurements` table is not used by the MVP; series are derived
from source records on demand.

Future schema changes add a named migration and preserve prior user data. Do not
enable erase-on-schema-change or use this derived cache as PR quota evidence.
Credentials never belong in this database.

Deterministic evidence: `Tests/SlopometerCoreTests/MeasurementCacheTests.swift`
covers repeat writes, isolation, unknown versus zero, rejected writes, and reopen
persistence. Human/provider checklist: [measurements and sync](../../testing/MANUAL%20TO-DO/measurements-and-sync.md).
