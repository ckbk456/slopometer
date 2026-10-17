# Sync and snapshot logic: implemented MVP

Owners: `Sources/SlopometerCore/SyncCoordinator.swift`, `GitHub/GitHubClient.swift`,
`GitHub/ProfileCalendarParser.swift`, `DashboardSnapshot.swift`, `App/AppModel.swift`.

## Tiers

- **Username only:** fetches `github.com/users/<login>/contributions` (undocumented
  HTML) and parses each day's tooltip. Markup that yields no days, or tooltips that
  do not match the cells, is an error, never zero activity. No credential is sent.
- **Token:** each saved token first calls GraphQL `viewer { login }`. A token owned by
  another account is reported (`tokenOwnerMismatch`) and not used. The first verified
  token fetches the GraphQL calendar in spans of at most one year; with none, the
  calendar falls back to the profile page. Every verified token fetches PRs through
  REST search, because each fine-grained token reads one resource owner's
  repositories. Per-token errors are in `SyncReport.tokenErrors`, keyed by token ID.
- **Token kinds:** `github_pat_` tokens are fine-grained; anything else is treated
  as classic and is accepted only with the InsecuSlopometer™ opt-in.

## PR fetch

Two searches cover the history window: `author:<login> type:pr created:<from>..<to>`
and the same with `merged:`, run per verified token. Results from every token are
merged by node ID. If any saved token could not be used, coverage is marked
incomplete because its repositories are missing. A window reporting more
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
The widget decodes it and never fetches or reads Keychain. Tokens live only in
Keychain (service `dev.slopometer.github-token`, one item per token ID); their names
and kinds are nonsecret preferences (`tokenEntries`). The single token saved by
earlier versions (account `default`) is adopted as "Personal".

macOS refuses App Group access to unsigned builds and to a copy signed differently
from the one that owns the container. A failed write is shown in the app window as
a widget notice (not a cache error); it does not block the dashboard.

The snapshot also carries `widgets`: one entry per size, built from
`DashboardSettings.widgets` (the Widgets tab), never from the Activity tab's metric or
view. The tab previews each size by rendering the shared `WidgetContent` view on the
same snapshot the widget reads. Each entry holds its headline choice, metric, view, today's
count, and a fixed window cut from the same daily series as `points` (history always
spans at least 182 days), without averages. Small shows the headline and the sync time;
medium shows a 7-day tile strip; large shows the 26-week grid, or the last 30 or 90 days
as columns or line. A quota headline falls back to today's count when no quota is
active. The widget distinguishes no readable snapshot ("No data yet"), no username, and
a size whose PR metric has no usable token. Settings saved before widget settings
existed decode with every size following the saved dashboard metric and view.
Activity marks are accent-tinted so levels survive the tinted desktop rendering. Medium
and large footers read `SyncAgeLabel` ("Synced 21:47 (00:02 ago)", naming the day when
the sync was not today); the timeline holds one entry per minute for an hour so the age
advances without the app. In the unfocused (non-full-color) desktop rendering, the
medium strip's busiest tiles (levels 3–4) cut their number out of the tile instead of
drawing near-white text on a near-white tile, and today's weekday is bold.

The dashboard replaces the chart with a token explanation when a PR metric is
selected without a usable token (missing, rejected, or owned by another account)
and links to the token section in Settings, so `tokenNeededNotice` is not repeated.

## Menu-bar badge

The menu bar shows the active quota's count/target when the snapshot contains a
quota; otherwise it shows today's count for the snapshot's selected metric, or
an en dash for unknown data. Its 16-point monochrome Octicon follows that same
metric: `calendar` for Contributions, `git-pull-request` for PRs opened, and
`git-merge` for authored PRs merged. Contributions cover GitHub's daily activity
count, not just commits; PRs opened includes drafts rather than measuring only drafts.

`AppModel` captures the badge metric with each successful snapshot rebuild, so an
active goal can differ from the chart without mislabeling its count, and a failed
rebuild retains the previous count and metric together. The tooltip and VoiceOver
label spell out the count and unit, or the metric with "no data yet". The app
bundles the original vector assets and their [Octicons license](../../App/Resources/Octicons-LICENSE.txt);
provenance is recorded in [third-party notices](../../THIRD_PARTY_NOTICES.md).

## App window layout and appearance (0.7.0)

Owners: `App/MainView.swift`, `App/SettingsView.swift`, `App/Glass.swift`.

- The Activity tab lays its content out with `FillingStack`: every item keeps its own
  height and the chart gets the rest of the visible height, never less than 220 pt.
  When the quota, day detail, or notices leave less than that, the chart keeps 220 pt
  and the tab scrolls. The available height comes from the scroll view's frame, not
  from the content, so resizing does not feed back into the layout. The grid keeps
  square cells, sized by the smaller of width and height, so a long range that is
  limited by width leaves its spare height below the notices rather than between rows.
- Settings keeps a one-line caption per access tier; the longer guidance (public-profile
  limits, fine-grained token setup and organization tokens, classic-token write access,
  timezone day labels) sits behind a `?` popover. Tier 3 is headed InsecuSlopometer™;
  its toggle reads "Allow classic tokens" and behaves as before.
- Before the repository picker or a `?` popover opens, a focused text field in the
  window gives up focus. A popover takes key status, and when it closed the window
  restored focus to the Username field, which selected its text and scrolled the form
  to the top. Menus do not take key status, so other pickers never did this.
- On macOS 26 and later the app's own cards (quota, token explanation, day detail), the
  tier badge, and the refresh and `?` buttons use Liquid Glass; controls inside a glass
  card stay borderless or bordered so glass is not stacked on glass. macOS 14 and 15, and
  builds made with an SDK before macOS 26 (CI uses Xcode 16.4), keep the earlier fills.
  Widgets are unchanged.

## Known limits

- In timezones ahead of the profile page's day labels, username-only "today" can be
  unknown until GitHub starts that day.
- No incremental sync yet; each sync repeats the full window.

Deterministic evidence: `Tests/SlopometerCoreTests/GitHubClientTests.swift` and
`SnapshotTests.swift`. Human/provider checklist: [measurements and sync](../../testing/MANUAL%20TO-DO/measurements-and-sync.md).
