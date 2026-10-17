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
- [ ] Settings order: GitHub connections (1 public account, 2 fine-grained tokens, 3 classic
      tokens behind InsecuSlopometer™), Pull requests, Timezone, About. Pull requests is
      grayed out without a token; Counts and Daily target stay visible but grayed out while
      the quota is off, and turning it back on restores their earlier values.
- [ ] Type a daily quota target (for example 100); values outside 1–999 snap into range.

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

## Widget and background app: pending

- [ ] App runs from the menu bar without a Dock icon; the window opens on demand.
- [ ] With only one signed copy running, the app shows no widget notice and the widget
      shows data in each size (unsigned or duplicate copies are refused the App Group).
- [ ] Widget can be added to the desktop and Notification Center in each size.
- [ ] Small shows the headline and "Synced <time>"; medium shows 7 labeled day tiles;
      large shows 26 weeks for grid and the chosen 30 or 90 days for columns/line, with
      no average line. Footer age is left, window label right, and does not shift.
- [ ] The window's tabs read Activity, Widgets, Settings. The Widgets tab shows a Small,
      Medium, and Large section, each with a preview matching the desktop widget. Changing
      a size's headline, metric, view, or window updates only that size and its preview;
      changing the Activity tab's metric or view changes no widget. Quota headline without an active quota shows
      today's count; a PR metric without a token shows the token message in that size.
- [ ] After upgrading from 0.5.0, each widget keeps the metric and view it showed before.
- [ ] With the desktop widget unfocused (tinted), grid levels, today's outline, tiles,
      and the quota meter stay distinguishable.
- [ ] Widget matches the app's counts and shows snapshot age when the app is quit.
- [ ] Medium and large footers read "Synced <time> (hh:mm ago)", the age advances each
      minute with the app quit, and a sync from an earlier day names that day.
- [ ] Unfocused desktop widget: medium tiles for the busiest days show their number cut
      out of the tile and readable; today's weekday label is bold in both renderings.
- [ ] Check Spaces, multiple displays, sleep/wake, and restart.
- [ ] Inspect custom palettes, density, contrast, and Reduce Motion.
- [ ] Verify login launch only after opting in; no orphan helper remains after quit.
- [ ] Test macOS 14 and other claimed supported versions on named targets.

Evidence: 2026-10-17, macOS 27.0.1, signed Debug build launched and quit cleanly by an
agent (no UI interaction). Every checklist item above remains pending.
