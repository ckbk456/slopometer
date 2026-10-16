# Sync and snapshot logic: implemented MVP

Owners: `Sources/SlopometerCore/SyncCoordinator.swift`, `GitHub/GitHubClient.swift`,
`GitHub/ProfileCalendarParser.swift`, `DashboardSnapshot.swift`, `App/AppModel.swift`.

## Tiers

- **Username only:** fetches `github.com/users/<login>/contributions` (undocumented
  HTML) and parses each day's tooltip. Markup that yields no days, or tooltips that
  do not match the cells, is an error, never zero activity. No credential is sent.
- **Token:** first calls GraphQL `viewer { login }`. A token owned by another account
  is reported (`tokenOwnerMismatch`) and not used; the calendar then falls back to
  the profile page. A verified token fetches the GraphQL calendar in spans of at
  most one year and PRs through REST search.

## PR fetch

Two searches cover the history window: `author:<login> type:pr created:<from>..<to>`
and the same with `merged:`. Results are merged by node ID. A window reporting more
than 1,000 results is split in half recursively; pages are fetched up to the
reported total. `incomplete_results` marks coverage incomplete. Each search request
waits 2.1 s to stay under the 30 requests/minute search limit, so a first sync of
about 900 PRs takes roughly a minute.

Every sync refetches the whole window (395 days: 365-day range plus 30-day warm-up)
and replaces cached records in one transaction. This reconciles delayed merges and
PRs that were deleted or became inaccessible, at the cost of repeated requests.

## Scheduling (app)

The app syncs at launch, then every 15 minutes, after wake when the last attempt is
over 10 minutes old, and on manual refresh. Overlapping syncs are skipped. Failures
back off exponentially from 2 minutes to 1 hour; rate limits wait until GitHub's
reset time. Changing the username clears the previous account's cache.

## Snapshot

`SnapshotBuilder` turns settings plus cache into `DashboardSnapshot`: points for the
selected range with unknown days as nil, a trailing average over completed days only
(today is marked incomplete and has no average), today's count, the quota with its
PR evidence, the last successful sync, and plain-language notices for missing token,
stale data (older than 45 minutes), incomplete coverage, and sync errors.

The app writes the snapshot as JSON to the App Group container
`5U4584QFCQ.dev.slopometer` and reloads widget timelines only when the bytes change.
The widget decodes it and never fetches or reads Keychain. The token lives only in
Keychain (service `dev.slopometer.github-token`).

## Known limits

- In timezones ahead of the profile page's day labels, username-only "today" can be
  unknown until GitHub starts that day.
- No incremental sync yet; each sync repeats the full window.

Deterministic evidence: `Tests/SlopometerCoreTests/GitHubClientTests.swift` and
`SnapshotTests.swift`. Human/provider checklist: [measurements and sync](../../testing/MANUAL%20TO-DO/measurements-and-sync.md).
