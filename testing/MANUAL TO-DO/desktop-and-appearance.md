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
- [ ] Type a daily quota target (for example 100); values outside 1–999 snap into range.

## Widget and background app: pending

- [ ] App runs from the menu bar without a Dock icon; the window opens on demand.
- [ ] With only one signed copy running, the app shows no widget notice and the widget
      shows data in each size (unsigned or duplicate copies are refused the App Group).
- [ ] Widget can be added to the desktop and Notification Center in each size.
- [ ] Widget matches the app's counts and shows snapshot age when the app is quit.
- [ ] Check Spaces, multiple displays, sleep/wake, and restart.
- [ ] Inspect custom palettes, density, contrast, and Reduce Motion.
- [ ] Verify login launch only after opting in; no orphan helper remains after quit.
- [ ] Test macOS 14 and other claimed supported versions on named targets.

Evidence: 2026-10-17, macOS 27.0.1, signed Debug build launched and quit cleanly by an
agent (no UI interaction). Every checklist item above remains pending.
