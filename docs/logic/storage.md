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

`eraseAll()` deletes every row in every table, sync state included, and keeps the
schema; Remove All Data uses it (see below).

## Remove All Data (1.0.3)

Owner: `AppModel.removeAllData()`. macOS runs nothing when the app is moved to the
Trash, so Settings › Uninstall offers this first. In order, it:

1. Stops polling and marks the model removed, so no new sync starts until relaunch.
2. Deletes every Keychain item under `vn.infinitex.slopometer.github-token`, querying by
   service only, so items whose entry was lost go too. The delete repeats until none
   remain. If Keychain refuses, it reports that and gives the Keychain Access fallback.
   The token list entries go with them.
3. Waits for a sync already running to finish, so it cannot write records back.
4. Erases the cache (`eraseAll()`), unregisters the login item, clears pending and
   shown notifications, deletes the App Group `snapshot.json`, and reloads widgets,
   so the widget shows its empty state.
5. Removes the app's preferences domain last, so nothing above writes one back.

The sheet then lists the deleted tokens by label and kind (and owner if known) and links
to GitHub's fine-grained or classic token page. Deleting a token locally leaves it
valid on GitHub, and the app does not revoke it. GitHub's public credential-revocation
endpoint exists, but it is built for reporting leaked credentials, so it is not used.
The only way out of the sheet is Quit.

Left behind: the empty `cache.sqlite` file, Sparkle's own caches, and the empty sandbox
and App Group container folders. macOS does not let a sandboxed app delete these. The
[README](../../README.md#uninstall) gives the manual steps.

Future schema changes add a named migration and preserve prior user data. Do not
enable erase-on-schema-change or use this derived cache as PR quota evidence.
Credentials never belong in this database.

Deterministic evidence: `Tests/SlopometerCoreTests/MeasurementCacheTests.swift`
covers repeat writes, isolation, unknown versus zero, rejected writes, and reopen
persistence. Human/provider checklist: [measurements and sync](../../testing/MANUAL%20TO-DO/measurements-and-sync.md).

## Quota history

The additive `createQuotaHistory` migration creates `quota_days` keyed by scope and
calendar day, storing the day's target and optional confirmed achievement count.
For PRs the scope includes account, metric, normalized repository filter, and timezone,
retaining the existing keys. Contributions use account, metric, `provider-calendar`,
and calendar source (`profilePage` or `graphQL`); they ignore repository and timezone
settings. This separates sources with different date labels without a destructive
migration. All scopes exclude the target. Sync record replacement leaves achievements intact.
Account reset and Remove All Data clear them. No credentials enter this table.
