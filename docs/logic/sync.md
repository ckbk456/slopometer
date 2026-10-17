# Sync and snapshot logic: implemented MVP

Owners: `Sources/SlopometerCore/SyncCoordinator.swift`, `Connection.swift`, `GitHub/GitHubClient.swift`,
`GitHub/ProfileCalendarParser.swift`, `DashboardSnapshot.swift`, `App/AppModel.swift`.

## Tiers

- **Username only:** fetches `github.com/users/<login>/contributions` (undocumented
  HTML) and parses each day's tooltip. Markup that yields no days, or tooltips that
  do not match the cells, is an error, never zero activity. No credential is sent.
- **Token:** each saved token first calls GraphQL `viewer { login }`. The first verified
  token fetches the GraphQL calendar in spans of at most one year; with none, the
  calendar falls back to the profile page. Every verified token fetches PRs through
  REST search, because each fine-grained token reads one resource owner's
  repositories. Per-token errors are in `SyncReport.tokenErrors`, keyed by token ID.
- **Account (0.9.0):** with tokens, the account is the token owner, not the typed username
  (`AccountResolver`): the owner of the earliest-added token whose owner is known. A
  fine-grained token whose resource owner is an organization is still owned by its
  creator, so it agrees. A token owned by anyone else is kept, reported as
  `tokenOwnerMismatch` ("Belongs to @x, not counted"), and not used; it marks PR coverage
  incomplete. A rejected token forgets its remembered owner, so the next token's owner can
  take over. Without a known owner (no tokens, or none checked yet), the typed username is
  the account; it stays stored while tokens exist and is used again when all are removed.
  `SyncReport` records the account it measured (`login`), the tokens it checked, and each
  token's owner. Owners are remembered with the token's nonsecret entry (`tokenEntries`).
- **Token standing:** `TokenState.resolve` uses the last report only when it was made for
  the current account and covered that token; otherwise it uses the remembered owner, or
  shows "Checking…". So a check for a previous account, or one made before a token was
  added, never reads as verified. A token counts when verified for the account, or when
  the last check could not reach GitHub but the token is known to belong to the account.
  The app treats a token as usable only then.
- **Connection wording:** `ConnectionLabel` names what is in use, counting only counted
  tokens: "Public profile (username only)", "Fine-grained tokens (N)", "Classic tokens (N)",
  or "Fine-grained + classic tokens (N)"; "Checking tokens…" while none is counted yet and
  some are unchecked. The Activity badge, Settings, and the menu bar panel use it. Token
  values are never shown.
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
over 10 minutes old, and on manual refresh. A refresh requested while a sync runs is not dropped: `RefreshGate`
queues one more run that starts as soon as the current sync ends and reads the settings and
tokens current at that moment, so adding or removing a token or changing the username always
syncs promptly. Those changes also discard the last report at once, so token rows show their
remembered owner or "Checking…" instead of a stale verdict. Failures back off exponentially
from 2 minutes to 1 hour; rate limits wait until GitHub's reset time. A new account's sync
clears the previous account's cache. Until then `SnapshotBuilder` treats a cache whose
`sync_state.login` names another account as empty: no counts, quota, PR evidence, or sync
time, and the notice "No data for @x yet. It appears after the next sync." The app's
evidence and repository list read nothing from such a cache either.

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
selected without a usable token (missing, still being checked, rejected, or owned by another account)
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

Clicking the badge opens a window-style panel (`MenuBarExtra` with `.window`, in
`App/MenuPanel.swift`) rather than a plain menu. It reads only the current snapshot
and app state; it never fetches on its own:

- **Headline:** a caption with the badge's Octicon. With an active quota it shows
  "Daily slop quota", count / target, "<unit> today in <scope>", the dashboard's
  status wording (Coverage incomplete, Target reached, or N to go), and the
  `QuotaMeter`. Otherwise it shows the badge metric's title and today's count, or an
  en dash when unknown. A PR metric without a usable token says it needs a token;
  without a username the panel asks the user to open Slopometer and enter one.
- **Last 7 days:** labeled day tiles for the badge metric, taken from a series the
  snapshot already holds (the dashboard's when its metric matches, else a widget's).
  The strip is hidden when no series matches or all seven days are unknown; unknown
  days show an en dash and today is outlined as incomplete.
- **Status rows:** sync state (syncing, relative time since the last successful sync,
  or not synced yet), the account with its connection wording on a second line, and every snapshot notice and
  widget sharing problem the headline does not already state, in the primary color.
- **Footer:** Refresh (⌘R, a spinner while syncing, disabled without a username), Open
  (⌘O, closes the panel and opens the window), Quit (⌘Q), and the build summary.
  macOS 26 and later use Liquid Glass button styles; earlier systems, and builds from
  SDKs before macOS 26 (`#if compiler(>=6.2)`), use bordered buttons.

## App window layout and appearance (0.7.0)

Owners: `App/MainView.swift`, `App/SettingsView.swift`, `App/Glass.swift`.

- The Activity tab lays its content out with `FillingStack`: every item keeps its own
  height and the chart gets the rest of the visible height, never less than 220 pt.
  When the quota, day detail, or notices leave less than that, the chart keeps 220 pt
  and the tab scrolls. The available height comes from the scroll view's frame, not
  from the content, so resizing does not feed back into the layout. The grid keeps
  square cells, sized by the smaller of width and height, so a long range that is
  limited by width leaves its spare height below the notices rather than between rows.
- Settings (0.9.0) has no numbered tiers. **GitHub** shows one summary row: an initial,
  @account (or "No account yet"), the connection wording, and sync status. **Tokens**
  lists every saved token (name, Fine-grained or Classic chip, then "Owned by @x, counted",
  "Belongs to @x, not counted", "Rejected by GitHub, not counted", "Not checked: …", or
  "Checking…") with Remove, then one Add Token… button, the creation link, and a `?`.
  Add Token… opens a sheet with Name and Token fields; the kind follows the prefix, and a
  classic token is refused unless InsecuSlopometer™ is on. Asking for the token section
  from the dashboard with no token saved opens the sheet. **Username** is editable only
  without tokens; with tokens it is grayed out and says "Using @x from your fine-grained
  tokens". **InsecuSlopometer™** is last, folded in a disclosure (open while the opt-in is
  on), with the "Allow classic tokens" toggle, disabled while classic tokens are saved.
  Longer guidance (token setup, organizations, account rule, public-profile limits,
  classic-token write access, timezone day labels) sits behind `?` popovers.
- The Activity header's connection badge shows the connection wording. Clicking it opens a
  popover listing each saved token's name, kind, and standing (as in Settings) and a
  "Manage in Settings" button that opens the token section. It holds no secrets.
- Before the repository picker, a `?` popover, or the Add Token sheet opens, a focused text field in the
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
