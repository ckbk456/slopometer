# Slopometer roadmap

Each phase is a coherent outcome with its own validation and handoff. These are
milestones, not date estimates or authorization to publish/merge/release.

| Phase | Outcome | Exit gate | Status |
| --- | --- | --- | --- |
| 0 · Bench setup | Native fixture preview, package/cache foundation, pinned dependencies, operating docs | Local deterministic gate; manual preview explicitly pending | CI passed on `main` (run 38923006922, Xcode 16.4); manual preview pending |
| 1 · Harden the bench | Single CI run per change, project drift check, consistent formatter and signing, widget extension with App Group and shared snapshot format | CI gate; widget appears from a locally signed build (manual) | Toolchain merged (#2); widget built and signed locally; manual widget check pending |
| 2 · Measure real slop | Source records, timezone bucketing, cache v2, public-profile calendar, optional token with GraphQL calendar and PR search, recorded fixtures | Reconciliation, deduplication, removed-PR, timezone, search-window, rate-limit, and token-mismatch tests | MVP: tests pass locally; live sync exercised on one account; manual provider checks pending |
| 3 · Set the daily quota | PR goals, evidence inspector, three charts, 7/30-day averages, widget views | Same-series chart/widget agreement; boundary, missing-data and quota tests | MVP: implemented without login launch or notifications; token gate, typed quota target, and fitted grid added; size-specific widget windows and per-size widget settings added; repository filter is a checklist of synced repositories; several tokens (one per organization) and opt-in classic tokens (InsecuSlopometer™); manual checks pending |
| 4 · Calibrate and package | Theme editor, saved configurations, accessibility, login launch, optional notification | Consolidated manual gates and explicit license/signing/distribution decisions | Theme editor implemented (0.12.0); release identity, MIT license, in-app updater, open at login, quota notification, saved configurations, density, and a source-level accessibility pass implemented (1.0.0); 1.0.1 published by hand (2026-10-20); release job planned; manual checks pending |

First technical priority: settle data contracts and widget plumbing before
visual polish. First data priority: agree on what counts before celebrating a
quota. Keep the token requirement explicit and avoid inventing an AI-quality score.

Data-source evidence behind the account-level, optional-token design is in
[GitHub data sources](docs/research/github-data-sources.md).

Update status only with evidence. Research belongs alongside the decision it
informs; it cannot override [SPEC](SPEC.md) or [SCOPE](SCOPE.md).

Settings fixes (1.0.2): Daily target accepts digits only, so a typed letter can no
longer pin focus to it and make the form jump back there when a color popover closes
(root cause reasoned from AppKit formatter behavior; manual check pending). Core tests
cover the digit filter and clamping. The shipped 1.0.2 build did not fix either bug in the
running app; see 1.0.4.

Settings field fixes (1.0.4): the user confirmed on 1.0.2 that letters still appeared in
Daily target and closing a color popover still scrolled the form to it. SwiftUI's
`TextField` does not redraw text its binding rewrites mid-edit, and its focus tracking put
focus back on the field. Daily target is now an AppKit field with a digits-only formatter,
outside SwiftUI focus tracking; `releaseWindowFocus()` also ends editing when a field will
not resign. Both causes are reasoned from AppKit and SwiftUI behavior; the user's local
check of a signed Debug build is pending before any release.

Menu-bar metric icons (0.3.1): implemented with calendar, pull-request, and merge
Octicons that follow the displayed count, plus full tooltip and accessibility
wording. `make validate` passed locally on 2026-10-17 (formatting, documentation,
39 core tests, unsigned native build); project regeneration is stable with
XcodeGen 2.46.0. The user accepted the menu-bar fix on 2026-10-17; the full
appearance/accessibility matrix remains pending.

Widget sync age and tinted contrast (0.6.1): medium and large footers show the sync
clock time with an hh:mm age that advances per minute from the widget's own timeline;
busiest medium tiles cut their number out when the desktop renders the widget in one
color. Implemented with core tests for the label; desktop rendering checks are pending.

App window polish (0.7.0): implemented on `codex/app-glass-polish`. The Activity chart
fills tall windows (minimum 220 pt, scrolling when content is taller); Settings captions
are condensed to one line per tier with longer guidance behind `?` popovers; tier 3 is
headed InsecuSlopometer™ with an "Allow classic tokens" toggle; the repository picker no
longer refocuses the Username field when it closes (root cause reasoned from AppKit
focus behavior, not yet observed fixed); the app's cards, badge, and small buttons use
Liquid Glass on macOS 26+ with the earlier look as fallback. Local validation is recorded
in the handoff; every UI check in the desktop manual guide remains pending.

Menu-bar panel (0.8.0): implemented the window-style menu-bar panel with the
metric's Octicon, a large headline count or quota with the quota meter and status,
a last-7-days strip from existing snapshot series, icon-led sync/account/notice
rows, and Refresh/Open/Quit buttons with their shortcuts (Liquid Glass on macOS 26+).
Local validation and manual checks are recorded in the
[desktop guide](testing/MANUAL%20TO-DO/desktop-and-appearance.md); the panel's
appearance, keyboard, and VoiceOver behavior are not yet manually verified.

GitHub connections (0.9.0): implemented on `codex/github-connections`. With tokens, the
account is the token owner (the earliest-added verified token; others owned by someone else
are kept but not counted), so a username is needed only without tokens; SPEC was updated on
the user's direction. Fixed a stale "Verified for @x" after a username change, previous-account
PR data shown under a new account until the next sync, and refreshes dropped while a sync was
running (now queued to run right after). Settings drops the numbered tiers for an account
Username section led by the account summary, then a token list with an Add Token sheet
ending in an InsecuSlopometer™ switch row; the Activity badge names the connection and lists tokens in a
popover. Core tests cover the identity, gating, and queueing rules; every UI and provider
check in the manual guides is pending.

Widget calendar and readable green (0.10.0): implemented on `codex/widget-calendar-green`.
The large widget's grid is a 5-week calendar (a column per weekday in the locale's order, a
row per week, the current week last) with the medium strip's numbered tiles filling the
height; its window aligns to whole weeks. Palette colors come from one `SlopTheme` with
roles for fills, text, and trend: light appearance uses a darker green (#116329, 6.78:1 on
#F5F5F5), dark keeps #2EA043 (4.94:1 on #1E1E1E), and tile numbers pick white or black per
level. Unfocused desktop tiles use white level fills and cut their number out from level 2.
The menu bar panel's background is mostly opaque. Core tests cover week alignment and
contrast targets; every rendering check in the
[desktop guide](testing/MANUAL%20TO-DO/desktop-and-appearance.md) is pending.

Sync speed and progressive display (0.11.0): search requests are paced by a shared rolling
budget instead of a fixed pause; a full sync fetches and publishes the last 30 days
before older history; every other sync fetches only PRs updated since each token's
checkpoint, with a full reconcile at least daily. Core tests cover the limiter, the
two-phase first sync, changes-only syncs, the daily reconcile, a new token, and
failed fetches. Human checks for live timing and the progressive display are pending.

One registered development build (0.11.1): `make run` also stops widget extension
processes launched from other checkouts' builds, and the app stamps the shared snapshot
with its version, build, and commit. The widget shows a one-line caption when its own
version or build differs from the app's. Core tests cover the stamp's tolerant decoding
and the comparison; the manual check in the
[desktop guide](testing/MANUAL%20TO-DO/desktop-and-appearance.md) is pending.

Color themes (0.12.0): Settings › Appearance offers gradient presets (Slop Electric default,
GitHub, Vibe Coded, Rainbow, Sunset, Ocean, Halloween, Mono, Viridis, Cividis) and
a custom gradient of 2–8 colors per appearance, with 4-level or Smooth mapping, automatic or
chosen accent, average-line color, and an accent or gradient quota meter. The app, menu bar
panel, and widget draw from the same saved theme; text and window backgrounds stay with the
system (SPEC updated on the user's direction). Readability advice is shown, never enforced.
Core tests cover OKLab mixing, readable text, sampling, Smooth mapping, presets, advice, and
settings migration; every rendering check in the
[desktop guide](testing/MANUAL%20TO-DO/desktop-and-appearance.md) is pending.

Theme editor polish (still 0.12.0, unreleased): a System/Light/Dark appearance switch for the
app, menu bar panel, and widget; saved themes (save, update, rename, delete); an in-place
color picker in a popover beside each gradient handle, accent, and average line instead of
the shared color panel; titled gradient actions; Less/More activity labels; drag to reorder
gradient colors; and a palette button on the dashboard that opens Settings › Appearance.
Saved theme tiles with their own dark colors show light above dark; "Same colors in dark
mode" sets the dark colors aside instead of discarding them, so turning it off restores
them. The widget sync age now reads "2m ago" or "1h 05m ago" instead of "00:02".
Core tests cover the new settings and snapshot fields; rendering checks are pending.

Release identity and updater (1.0.0): implemented on `codex/sparkle-updater` on the user's
direction (SCOPE updated). The app, widget, App Group, and Keychain service moved to
`vn.infinitex.slopometer`, so earlier development data is not carried over. Sparkle 2.10.0
checks `https://updates.infinitex.vn/slopometer/appcast.xml` daily in release builds (off
by default in Debug), with Settings › Updates and a menu bar panel reminder; the EdDSA key
was generated in the release machine's Keychain. The version is 1.0.0 on the user's
direction; login launch, the notification, and saved configurations followed below. Next: a tagged-release job (Developer ID archive, notarization, appcast,
upload to R2). Updater and identity checks in the
[desktop guide](testing/MANUAL%20TO-DO/desktop-and-appearance.md) are pending.

Open at login (1.0.0): implemented on `codex/launch-at-login` with `SMAppService.mainApp`
behind Settings › General, off by default, reading the system status back (including
approval pending). Checks in the [desktop guide](testing/MANUAL%20TO-DO/desktop-and-appearance.md)
are pending.

Quota notification (1.0.0): implemented on `codex/quota-notification`. Opt-in "Notify
when reached" under Settings › Pull requests posts one notification per goal and day,
only after a sync confirms PR data with complete coverage. Core tests cover the rules;
the checks in the [measurements guide](testing/MANUAL%20TO-DO/measurements-and-sync.md)
are pending.

Saved configurations (1.0.0): implemented on `codex/saved-configurations` as Activity
presets on the user's direction (SPEC updated): metric, repository filter, chart, range,
average, theme, and quota, saved and managed from the Activity tab and switched there or
from the menu bar panel. Widgets keep their per-size settings. Density does not exist yet,
so it is not part of a configuration. Core tests cover capture, apply, edit detection, and
decoding; the checks in the [desktop guide](testing/MANUAL%20TO-DO/desktop-and-appearance.md)
are pending.

Density and accessibility (1.0.0): implemented on `codex/density`. Settings › Appearance ›
Density (Comfortable/Compact) sets control size and spacing in the app window and menu bar
panel; widgets keep system sizes. A source review added VoiceOver labels to column/line
chart marks, made the two animations respect Reduce Motion, and hid decorative icons.
Earlier work already labels heatmap and widget tiles, the color picker, and swatches. No
person has run the accessibility checks; they are in the
[desktop guide](testing/MANUAL%20TO-DO/desktop-and-appearance.md).

Default theme (1.0.0): Slop Green is removed because it read as GitHub's
own green. Slop Electric, retuned to an ordered electric blue to indigo ramp, is the first
preset and the default, including for the widget before the app writes a snapshot. Core
tests cover the default's contrast targets and advice; rendering checks are pending.

Pre-release cutover (1.0.0): nothing was released before 1.0.0, and the new identity starts
with empty preferences, cache, and Keychain, so code that adopted earlier development data
was removed: the single-token Keychain adoption, the 0.5.0 widget-settings fallback, the
Slop Green theme mapping, and `make run`'s handling of the old bundle ID. Missing settings
still decode to their defaults, which protects 1.0.x itself.

Polish after the first 1.0.0 test (1.0.0): a 180-day range joins 30/90/365 (SPEC and SCOPE
updated on the user's direction); the window's sections are a segmented control in the
toolbar instead of a TabView, whose tab strip macOS 26 drew as a cramped capsule; "Same
colors in dark and light mode" shares whichever palette is being edited and saves the
other in settings, so customization is never hidden or lost, and pending color edits are
kept when leaving Settings. Manual checks in the
[desktop guide](testing/MANUAL%20TO-DO/desktop-and-appearance.md) are pending.

Timezone picker (1.0.0): Settings › Timezone is a searchable popover (city, region, IANA
identifier, zone name, or offset such as "+7"), listed west to east with each zone's
current GMT offset and a "Use This Mac's Timezone" shortcut, instead of a menu of 400
identifiers. `TimeZoneChoice` in the core holds the naming and search, with tests.

Token cache hotfix (1.0.1): development builds sent GitHub requests through the shared URL
session, whose disk cache stored them with the Authorization header (found by a Codex audit,
confirmed against the caches of earlier builds). The transport now uses a session that keeps
no cache, cookies, or credentials; authorized requests ignore caches; launch empties the
shared cache and removes earlier builds' cache files; a refused Keychain delete keeps the
token listed with a notice. 1.0.0 was never published, so 1.0.1 is the first public build.
Core tests cover the session configuration and the request cache policy; the checks in the
[measurements guide](testing/MANUAL%20TO-DO/measurements-and-sync.md) are pending.

First public release (1.0.1, build 23, `13a87fd`): published by hand on 2026-10-20. The
notarized DMG, update archive, and Sparkle feed are on `updates.infinitex.vn/slopometer/`,
the download site is live on `slopometer.infinitex.vn`, and GitHub release `v1.0.1`
mirrors the DMG. Steps are in the [updates guide](docs/logic/updates.md); a release job
is still planned. Install and update checks in the
[desktop guide](testing/MANUAL%20TO-DO/desktop-and-appearance.md) are pending.

Branded installer (1.0.2): implemented the website-inspired static DMG background
with standard/Retina representations, explicit drag-to-Applications guidance and
a gauge app/volume icon. Editable vectors, bundled OFL fonts and locked artwork/
DMG commands make packaging repeatable. Local validation and release evidence are
reported with delivery; Finder visual/drag-install and supported-OS checks remain
pending in the desktop guide.

Installer signature preservation (1.0.2): release verification caught that
forcing a hidden app extension adds disallowed Finder metadata after signing.
Packaging no longer writes it and now strictly verifies identity-signed apps
both before copying and from the completed image. This gate is separate from
Apple's app/DMG notarization and the pending Finder UI checks.

Versioned download (after 1.0.3): the download site now links to
`Slopometer-<version>.dmg` instead of the fixed `Slopometer.dmg`, which a browser had
served from cache as 1.0.1 after 1.0.2 and 1.0.3 replaced it. Versioned images are
immutable; the fixed name stays as a `no-cache` copy for older links. Release steps are in
the [updates guide](docs/logic/updates.md). The download check in the
[desktop guide](testing/MANUAL%20TO-DO/desktop-and-appearance.md) is pending.

Remove All Data (1.0.3): Settings › Uninstall › Remove All Data… deletes every Keychain
token item, the cache, the widget snapshot, preferences, the login item, and notifications.
It then lists the deleted tokens with links to revoke them on GitHub, and quits. SPEC and
SCOPE were updated on the user's direction, and the README gained uninstall steps. Core
tests cover `MeasurementCache.eraseAll()`. The checks in the
[measurements guide](testing/MANUAL%20TO-DO/measurements-and-sync.md) are pending.
