# Desktop and appearance

## MVP app window: pending

- [ ] Launch via `make run`; first launch opens Settings when no username is set.
- [ ] Switch grid/columns/line, ranges, and averages; click a day to see its detail.
- [ ] Close and reopen the window from the menu bar; verify Quit exits the app.
- [ ] Inspect keyboard operation, VoiceOver, and light/dark contrast.
- [ ] At the minimum window width, controls stay on their rows and the grid has no empty
      gap below it for 30, 90, and 365 days.
- [ ] Without a token, PRs opened / Authored PRs merged show the token explanation; Add
      Token opens Settings scrolled to the token field. Rejected or mismatched tokens show
      their own wording.
- [ ] Settings order: Username, Tokens (InsecuSlopometer™ last; see 0.9.0 below), Pull
      requests, Timezone, About. Pull requests is
      grayed out without a token; Counts and Daily target stay visible but grayed out while
      the quota is off, and turning it back on restores their earlier values.
- [ ] Type a daily quota target (for example 100); values outside 1–999 snap into range.

## App window polish (0.7.0): pending

- [ ] Focus the Username field, scroll Settings down, open Pull requests › Repositories
      (with and without more than 8 repositories, so with and without the search field),
      then click elsewhere to close it. The form keeps its scroll position and the
      Username text is not selected. Repeat with each `?` popover.
- [ ] Each GitHub connections tier shows a one-line caption and a `?` button; each `?`
      (and the Timezone `?`) opens readable guidance, closes with Esc or a click outside,
      and is announced by VoiceOver as "About …". The fine-grained token link stays visible.
- [ ] Tier 3 reads InsecuSlopometer™; "Allow classic tokens" keeps its orange tint, is
      disabled while classic tokens are saved, and shows its note.
- [ ] Resize the window from 640×540 to full-screen height: columns and line charts fill
      the height smoothly without jitter; the grid grows with square cells and never
      overflows the width for 30, 90, and 365 days. With the quota card, day detail, or
      notices showing, the chart keeps at least its minimum height and the tab scrolls.
- [ ] On macOS 26+: quota card, token explanation, day detail, tier badge, refresh and `?`
      buttons render as Liquid Glass, legible in light/dark and with Reduce Transparency
      and Increase Contrast. On macOS 14/15: the earlier gray cards and borderless buttons.
- [ ] Condensed wording reads clearly and still says which features need a token.

## GitHub connections (0.9.0): pending

- [ ] Settings shows no numbered markers and no GitHub heading. Username comes first: a row
      with the account's initial, @account, the connection wording, and sync status, then
      the username field. Tokens: one row per token (name, Fine-grained/Classic chip,
      standing line, Remove), then Add Token…, the creation link, and `?`, then the
      InsecuSlopometer™ row with its switch on the right.
- [ ] Add Token… opens a sheet focused on the token field; Esc cancels; an empty token
      disables Add Token; a classic token with InsecuSlopometer™ off shows the refusal; a
      duplicate says it is already saved. The token value never appears afterwards.
- [ ] Without a token, the dashboard's Add Token opens Settings with the sheet; with tokens,
      Review Tokens scrolls to the token list. Add Username focuses the username field.
- [ ] With a token saved, the username field is grayed out and reads "Using @owner from your
      fine-grained tokens"; removing every token makes it editable again with the earlier name.
- [ ] Connection wording is identical in the Activity badge, Settings summary, and the menu
      bar panel's account row: "Public profile (username only)", "Fine-grained tokens (N)",
      "Classic tokens (N)", or "Fine-grained + classic tokens (N)", counting only counted tokens.
- [ ] Clicking the Activity badge opens a popover listing each token's name, kind, and
      standing (counted, not counted with reason, or checking) with no secrets; "Manage in
      Settings" closes it and opens the token section. VoiceOver reads the badge as
      "Connection: …".
- [ ] The InsecuSlopometer™ switch turns classic tokens on and off; it is disabled while classic
      tokens are saved; scroll position stays put when `?` popovers or the sheet close.
- [ ] Light/dark, Increase Contrast, and macOS 14/15 versus 26+ rendering stay legible.

## Menu-bar metric icons (0.3.1): pending

Acceptance: on 2026-10-17 the user reported being happy with the fix and authorized
publication and merge. This is acceptance of the observed fix; the individual
checks below were not separately reported and remain pending.

- [ ] Without a quota, switch Contributions / PRs opened / Authored PRs merged and
      verify the badge shows the calendar / pull-request / merge icon with today's count.
- [ ] With a quota enabled, change its metric between PRs opened and authored PRs merged;
      the icon and count/target follow the quota even when the chart shows another metric.
- [ ] Disable the quota or remove its token; the badge returns to the selected metric.
      Missing data shows an en dash, never a fabricated zero.
- [ ] Hover the badge and inspect it with VoiceOver: the full metric and count are
      announced, including the quota target or "no data yet" when appropriate.
- [ ] Check all three icons in light/dark appearance and a selected menu-bar item,
      on Retina and non-Retina displays where available; verify crisp, compact shapes.

## Menu-bar panel (0.8.0): pending

- [ ] Clicking the badge opens a rounded panel (not a menu); the badge itself is unchanged.
- [ ] With a quota: caption "DAILY SLOP QUOTA" with the quota metric's icon, count / target,
      "<unit> today in <scope>", status (Target reached / N to go / Coverage incomplete),
      and the tick meter agree with the dashboard's quota card.
- [ ] Without a quota: the selected metric's title, icon, and today's count; unknown
      shows an en dash, never zero.
- [ ] The last-7-days strip matches the dashboard (or medium widget) for the same metric,
      shows en dashes for unknown days, and is absent when all seven days are unknown.
- [ ] No username: the panel asks to open Slopometer and enter a username; its Open
      button and Open in the footer bring the window forward and close the panel.
- [ ] PR metric without a token: the headline explains the token requirement and the
      token notice is not repeated in the rows.
- [ ] Sync row shows "Syncing with GitHub…" while Refresh spins, then "Synced <time> ago";
      account row shows @login with the connection wording below it; notices are readable.
- [ ] ⌘R, ⌘O, and ⌘Q work while the panel is open; Refresh is disabled without a username.
- [ ] VoiceOver reads the headline (headline wording plus status), the meter's "N of M",
      each day tile, and the Refresh/Open/Quit buttons by name.
- [ ] Light and dark appearance, Increase Contrast, and Reduce Transparency stay legible.
- [ ] macOS 26 or later shows Liquid Glass buttons; macOS 14/15 show bordered buttons.
- [ ] A build from Xcode 16.4 (macOS 15 SDK, as in CI) compiles the non-glass path.

## Widget calendar and readable green (0.10.0): pending

- [ ] Large widget, Grid view: a weekday header row in the locale's order (Monday first in
      a Monday-first region), then 5 week rows with the current week last; tiles fill the
      height with even gaps and no empty band above or below; days after today are empty,
      unknown days show an en dash, today is outlined and its weekday bold. Footer reads
      "Last 5 weeks"; the Widgets tab's Window row says the same and its preview matches.
- [ ] Counts fit their tiles (including three-digit counts) and match the Activity tab for
      the same days and metric. The Activity tab's own grid is unchanged.
- [ ] Unfocused desktop widget (desktop not active): medium and large tiles from level 2 up
      show their number cut out and readable; low levels show a readable number; levels stay
      distinguishable; bars, line, and quota ticks stay visible. Repeat on a light and a dark
      wallpaper, and with a tinted/accented widget style if the system offers one.
- [ ] Light appearance: the green in the app (Target reached, Token badge, key icon, tiles,
      columns, segmented/toggle tint, the prominent Add Token button) reads as a darker green;
      dark appearance looks as before. Tile numbers are readable on every level.
- [ ] Menu bar panel over a busy or bright wallpaper, light and dark: background is mostly
      opaque, "Target reached", "Token", meter ticks, and 7-day tiles are readable; Increase
      Contrast and Reduce Transparency still look right.

## One registered build (0.11.1): pending

- [ ] With builds in two worktrees, `make run` in one prints "Stopped widget … from another
      build" for the other build's running widget extension (if any) and never stops a
      process under its own `Slopometer.app`; the desktop widget then follows this build.
- [ ] While another worktree's app is still running, `make run` warns "Still running, quit
      it first" and leaves that build registered.
- [ ] When the widget runs from a different version or build than the app that wrote the
      snapshot, it shows "Widget build differs from app. Reopen Slopometer." in each size;
      with matching builds, or a snapshot from before 0.11.1, no caption appears. The
      app's Widgets tab preview never shows it.

## Color themes (0.12.0): pending

- [ ] Settings › Appearance: each preset changes the Activity grid, columns, line, quota
      meter, tint, menu bar panel, Widgets tab previews, and desktop widgets together, in
      light and dark appearance.
- [ ] Slop Electric is the first preset and selected on a fresh install; Reset to Slop
      Electric restores it; no Slop Green preset is offered. A new widget placed before the
      app has run shows Slop Electric.
- [ ] Custom gradient: add up to 8 and remove down to 2 colors, edit by picker and hex,
      Reverse, Surprise Me; the caption switches to "Edited from …, not saved"; the choice
      survives relaunch.
- [ ] Clicking a gradient handle opens the color picker in a popover right under it (on a
      multi-display setup too); dragging inside it, the hue bar, and hex entry update the
      gradient and previews live; Remove Color sits in the same popover. Accent and Average
      line swatches open the same picker. The system color panel never appears.
- [ ] Dragging a handle left or right reorders the gradient; VoiceOver offers Move left/right.
- [ ] "Less activity" and "More activity" labels sit under the gradient's ends; buttons are
      titled (Add Color, Reverse, Surprise Me) and show tooltips.
- [ ] Save as New Theme names and selects a saved theme under "Your themes"; editing it
      shows Update "Name"; right-click Rename, Update with Current Colors, and Delete work;
      saved themes survive relaunch.
- [ ] Appearance System/Light/Dark switches the window, menu bar panel, and desktop widget
      (background included) at once; System follows the macOS switch again.
- [ ] The palette button on the dashboard opens Settings scrolled to Appearance.
- [ ] "Same colors in dark mode" off: light and dark edit separately and both previews and
      the real app follow the system appearance switch.
- [ ] Smooth mapping with Rainbow: neighboring counts get visibly different colors; 4 levels
      shows 4. Tile numbers stay readable on every color, including yellow.
- [ ] Gradient meter: ticks walk the gradient; targets over 20 show a gradient track.
- [ ] Advice captions appear for Rainbow (lightness) and a flat custom gradient (similar
      levels) and disappear for GitHub/Viridis.
- [ ] Accent text (Target reached, Token badge, "+N") stays readable with Halloween's
      yellow and Slop Electric's sky blue; warnings stay amber in every theme.
- [ ] Unfocused/tinted desktop widget ignores the theme and stays readable.
- [ ] A saved theme with its own dark colors shows light above dark in its tile, in both
      window appearances; a saved theme without them shows one strip.
- [ ] With separate dark colors, turning "Same colors in dark mode" on shows a note, and
      turning it off brings the dark colors back; on a saved theme or preset the
      selection stays when the colors return to what was saved.
- [ ] VoiceOver names each preset and control; the selected preset is marked by more
      than color; Increase Contrast and Reduce Transparency remain legible.

## Release identity and updates (1.0.0): pending

- [ ] After `make run`, only the 1.0.0 build is registered: the widget gallery offers one
      Slopometer, and `slopometer://` links open it. Earlier `dev.slopometer.app` widgets
      are gone or show no data and must be re-added.
- [ ] The app starts empty (new identity): enter the username and tokens again; sync,
      the menu bar, and the widget work as before.
- [ ] Settings › Updates shows "Check for updates automatically" (off in Debug) and
      "Check for Updates…". Before a feed is published, checking reports that the update
      server cannot be reached, with no crash or hang.
- [ ] Settings › About and the menu bar panel read version 1.0.0.
- [ ] After a feed is published: an older release finds the newer one, the alert shows
      release notes, Install relaunches into the new version, and data and widgets are kept.
- [ ] A scheduled check (release build) shows a Dock icon and the menu bar panel row
      "Slopometer x is available"; clicking the row brings the alert forward; both clear
      after the alert is dismissed.

## Open at login (1.0.0): pending

- [ ] Settings › General › "Open at login" is off on a fresh install. Turning it on adds
      Slopometer to System Settings › General › Login Items; logging out and in starts it
      in the menu bar without opening the window.
- [ ] Turning it off in System Settings is reflected by the toggle when the app comes
      back to the front; turning it off in the app removes the login item.
- [ ] If macOS asks for approval, the caption and "Open Login Items" appear and lead to
      the right System Settings page.
- [ ] A Debug build registers its own `.build` path; turn the toggle off before deleting
      a worktree, or the login item points at a missing app.

## Saved configurations (1.0.0): pending

- [ ] Activity › Configurations › "Save as New Configuration…" names and saves the current
      metric, repositories, chart, range, average, colors, and quota; the menu then shows
      its name with a checkmark.
- [ ] Changing any of those marks it "(edited)"; "Update" saves the change; choosing it
      again discards the edit. Changing light/dark, timezone, or a widget does not mark it.
- [ ] Switching between two configurations changes the chart, colors, and quota (or turns
      the quota off and back on with the earlier target), the menu bar headline, and
      nothing in the Widgets tab.
- [ ] The menu bar panel shows a configuration row only when some are saved; it switches
      but does not offer save, rename, or delete.
- [ ] Rename and Delete work from the Activity menu; deleting the one in use keeps the
      dashboard as it is. Configurations survive relaunch.
- [ ] VoiceOver reads "Configuration: <name>" for both menus.

## Density and accessibility pass (1.0.0): pending

- [ ] Settings › Appearance › Density switches Comfortable/Compact at once: smaller
      controls and tighter spacing in the Activity tab, Settings, and the menu bar panel
      (narrower, shorter rows); widgets are unchanged; the choice survives relaunch and is
      not marked as a configuration edit.
- [ ] VoiceOver on a columns or line chart reads each day as "<date>: <n> <unit>" (today
      "so far") and average points as "<date>: average <x> <unit>".
- [ ] With Reduce Motion on, showing/hiding the quota's PRs and jumping to a Settings
      section happen without animation.
- [ ] VoiceOver does not read symbol names for token status icons, PR rows, or the widget's
      empty-state gauge.

## Widget and background app: pending

- [ ] App runs from the menu bar without a Dock icon; the window opens on demand.
- [ ] With only one signed copy running, the app shows no widget notice and the widget
      shows data in each size (unsigned or duplicate copies are refused the App Group).
- [ ] Widget can be added to the desktop and Notification Center in each size.
- [ ] Small shows the headline and "Synced <time>"; medium shows 7 labeled day tiles;
      large shows a 5-week calendar for grid and the chosen 30 or 90 days for columns/line, with
      no average line. Footer age is left, window label right, and does not shift.
- [ ] The window's tabs read Activity, Widgets, Settings. The Widgets tab shows a Small,
      Medium, and Large section, each with a preview matching the desktop widget. Changing
      a size's headline, metric, view, or window updates only that size and its preview;
      changing the Activity tab's metric or view changes no widget. Quota headline without an active quota shows
      today's count; a PR metric without a token shows the token message in that size.
- [ ] With the desktop widget unfocused (tinted), grid levels, today's outline, tiles,
      and the quota meter stay distinguishable.
- [ ] Widget matches the app's counts and shows snapshot age when the app is quit.
- [ ] Medium and large footers read "Synced <time> (2m ago)" or "(1h 05m ago)", the age advances each
      minute with the app quit, and a sync from an earlier day names that day.
- [ ] Unfocused desktop widget: medium tiles for the busiest days show their number cut
      out of the tile and readable; today's weekday label is bold in both renderings.
- [ ] Check Spaces, multiple displays, sleep/wake, and restart.
- [ ] Inspect density, contrast, and Reduce Motion.
- [ ] Test macOS 14 and other claimed supported versions on named targets.

Evidence: 2026-10-17, macOS 27.0.1, signed Debug build launched and quit cleanly by an
agent (no UI interaction). Every checklist item above remains pending.
