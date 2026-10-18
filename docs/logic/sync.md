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

Two searches cover a window: `author:<login> type:pr created:<from>..<to>` and
`merged:<from>..<to> created:<<from>` (PRs created before the window and merged in it,
so the two searches do not return the same PRs twice). They run per verified token
and results from every token are merged by node ID. If any saved token could not be
used, coverage is marked incomplete because its repositories are missing. A window
reporting more than 1,000 results is split in half recursively; pages are fetched up
to the reported total. `incomplete_results` marks coverage incomplete.

`SearchRateLimiter`, shared by every token because GitHub counts search requests per
account, sends up to 28 search requests per rolling minute without waiting and sleeps
only when that budget, or the budget GitHub reports in `X-RateLimit-Remaining`, is
spent. A first sync of about 900 PRs is bounded by network time, not by pauses.

**Full reconcile** (first sync for an account, a verified token without a checkpoint,
a window that starts earlier than the cached coverage, or at least 24 hours since the
last full reconcile): the last 30 days are fetched for every token and written first,
so today's counts and the widget update within a few requests, then the rest of the
395-day window (365-day range plus 30-day warm-up). When every verified token covered
the whole window, the cached records are replaced in one transaction, which removes
PRs that were deleted or became inaccessible. Until older history is in, or when it
fails, coverage starts at the recent window, so older days are unknown rather than
zero, and the failed token has no checkpoint, so the next sync refetches the window.

**Changes only** (every other sync): one search per token,
`updated:<checkpoint − 6 h>..<now>`, returns PRs created or changed since that
token's checkpoint, including an older PR merged today. The overlap covers GitHub's
search indexing delay. Records are inserted or updated by node ID; nothing is deleted.
PRs outside the window that were touched for other reasons are ignored. A token whose
fetch fails keeps its records and checkpoint and is reported in `pullRequestError`;
`rateLimited` and `offline` stop the remaining tokens. Checkpoints advance only after
a token's fetch succeeds. `SyncReport.pullRequestSyncMode` records which path ran.

Deleted PRs and lost repository access are only reconciled by the daily full pass.

## Progress

`SyncCoordinator.sync` reports each stage as it starts (`SyncProgress`: checking
tokens, updating calendar, fetching recent PRs, loading older PRs, fetching PR
changes) with whether an earlier stage already wrote to the cache. `AppModel` shows
the stage in the refresh controls and rebuilds the snapshot, including the widget's,
whenever the cache changed, so the calendar and recent PRs appear before older
history finishes.

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
`5U4584QFCQ.vn.infinitex.slopometer` and reloads widget timelines only when the bytes change.
The widget decodes it and never fetches or reads Keychain. Tokens live only in
Keychain (service `vn.infinitex.slopometer.github-token`, one item per token ID); their names
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
spans at least `WidgetSettings.minimumHistoryDays`, 90 days), without averages. Small shows
the headline and the sync time; medium shows a 7-day tile strip; large shows a calendar
grid of the last 5 weeks, or the last 30 or 90 days as columns or line. A quota headline falls back to today's count when no quota is
active. The widget distinguishes no readable snapshot ("No data yet"), no username, and
a size whose PR metric has no usable token. Settings saved before widget settings
existed decode with every size following the saved dashboard metric and view.
The large calendar grid has a column per weekday, starting from the locale's first
weekday (`Calendar.firstWeekday`, passed to `SnapshotBuilder.build`), and a row per week
with the current week last. Its window is the four earlier full weeks plus the current week
through today (29–35 days), so the first point starts a week; `WidgetSettings.calendarRows`
lays the points out and leaves days after today empty rather than zero. A weekday header row
sits above the rows, which share the remaining height evenly (about 44 × 44 pt tiles at the
large size). Tiles are the medium strip's `DayTile`: the count on the level fill, an en dash
for unknown days, today outlined and its weekday bold. A snapshot from an earlier version (26-week window)
still renders: the grid keeps its last 5 weeks.
Activity marks are accent-tinted so levels survive the tinted desktop rendering. Medium
and large footers read `SyncAgeLabel` ("Synced 21:47 (2m ago)", "(1h 05m ago)", naming the day when
the sync was not today); the timeline holds one entry per minute for an hour so the age
advances without the app. In the unfocused or tinted (non-full-color) desktop rendering,
`DayTile` fills levels with white at fixed opacities (12, 30, 50, 75, 100 %) instead of the
green, so levels do not depend on the hue's brightness; from level 2 up the number is cut
out of the tile (`.destinationOut` in a compositing group) instead of drawing near-white
text on a bright tile, and today's weekday is bold. Bars, line, and filled quota ticks are
white there too.

## Palette roles and themes

A person picks a `ColorTheme` (`Sources/SlopometerCore/SlopTheme.swift`) in Settings ›
Appearance: a preset from `ThemePreset.all` (`ThemePreset.swift`) or their own edit of one.
It is saved in `DashboardSettings.theme` and copied into the widget snapshot
(`DashboardSnapshot.theme`; nil in older snapshots means the standard theme), so the app,
menu bar panel, and widget draw the same colors. A theme holds, per appearance (dark may
reuse light; while it does, the editor keeps the previous dark colors in view state until
another theme is chosen or Settings closes, so turning sharing off restores them):

- `gradient`: 2–8 evenly spaced colors, low to high activity, mixed in OKLab.
- `accent`: control tint, badges, highlighted numbers, the daily line; nil picks the
  gradient color with the most contrast on the background.
- `trend`: the moving average line.

plus `mapping` (`levels`: GitHub-style levels 1–4 sample the gradient at 0, ⅓, ⅔, 1;
`continuous` ("Smooth"): count 1 maps to the first color and the busiest visible day to the
last, so every count gets its own color) and `meter` (quota ticks in the accent, or walking
the gradient from the first tick to the target).

`resolved()` turns a theme into `SlopTheme`, the roles views read: accent text is the
accent moved in lightness until it reaches 4.5:1 on the reference background (#F5F5F5
light, #1E1E1E dark), the trend reaches 3:1, and `warning` (incomplete coverage, modified
builds) is a fixed amber that is not themable. Text and window backgrounds are not themable
either. Each tile's number is white or black, whichever contrasts more with its fill. Views
read the resolved colors from `@Environment(\.slopColors)`, set by `.slopTheme(_:)`
(`Shared/ThemeEnvironment.swift`) at the window, panel, and widget roots for the current
color scheme. `DashboardSettings.appearance` (System, Light, Dark) sets `NSApp.appearance`
for the window and menu bar panel and travels in `DashboardSnapshot.appearance` (nil means
System); a forced widget sets its color scheme before resolving the theme and draws the
matching reference background instead of the system fill. `DashboardSettings.savedThemes`
holds named `SavedTheme`s; a saved theme's id is also its theme's `presetID`, so it stays
selected until edited, and the editor remembers it as the origin so it can be updated in
place. Editing clears `presetID`, as for presets. Column bars take their day's fill; the tinted/unfocused widget rendering
ignores the theme and keeps the white levels described above.

`ThemeAdvice.check` warns, without blocking, when neighboring levels are hard to tell apart
(below 1.15:1), when lightness does not rise steadily (the grid view has no numbers, so a
rainbow reads as hue only; hovering a day shows its count), or when level 1 nearly vanishes
into the background (below 1.2:1). Mono, Viridis, and Cividis are marked colorblind-safe.

The default, Slop Electric (`ThemePreset.electric`, id `electric`), runs electric blue to
indigo: #93C5FD, #3B82F6, #4F46E5, #3730A3 in light and #312E81, #4338CA, #3B82F6, #7DD3FC
in dark. Neighboring levels differ by at least 1.45:1 and lightness is ordered, so it draws
no advice. The earlier Slop Green preset was removed; a stored theme whose `presetID` is
`slop-green` decodes as the default.

| Role | Light (vs #F5F5F5) | Dark (vs #1E1E1E) |
| --- | --- | --- |
| Slop Electric accent / text | #3730A3, 9.11:1 | #7DD3FC, 10.0:1 |
| Slop Electric trend | #BE185D, 5.54:1 | #F472B6, 6.29:1 |
| Other presets' default trend; warning | #8A5C00, 5.33:1 | #D29922, 6.60:1 |

`SlopThemeTests` checks the standard targets and, for every preset, accent text 4.5:1,
trend 3:1, and warning 4.5:1 in both appearances. The menu bar panel draws the window
background at 82 % opacity behind its content, so the wallpaper does not wash out the
colors.

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
- Settings (0.9.0) has no numbered tiers and no separate GitHub heading. **Username**
  comes first: one summary row (an initial, @account or "No account yet", the connection
  wording, and sync status), then the username field. **Tokens**
  lists every saved token (name, Fine-grained or Classic chip, then "Owned by @x, counted",
  "Belongs to @x, not counted", "Rejected by GitHub, not counted", "Not checked: …", or
  "Checking…") with Remove, then one Add Token… button, the creation link, and a `?`.
  Add Token… opens a sheet with Name and Token fields; the kind follows the prefix, and a
  classic token is refused unless InsecuSlopometer™ is on. Asking for the token section
  from the dashboard with no token saved opens the sheet. The username is editable only
  without tokens; with tokens it is grayed out and says "Using @x from your fine-grained
  tokens". **InsecuSlopometer™** is the last row of Tokens: its name, a one-line caption,
  a `?`, and the "Allow classic tokens" switch on the right, disabled while classic tokens
  are saved.
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
- Incremental syncs cannot see deleted PRs or lost repository access; those wait for
  the daily full reconcile.

Deterministic evidence: `Tests/SlopometerCoreTests/GitHubClientTests.swift` and
`SnapshotTests.swift`. Human/provider checklist: [measurements and sync](../../testing/MANUAL%20TO-DO/measurements-and-sync.md).
