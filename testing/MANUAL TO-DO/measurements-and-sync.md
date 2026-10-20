# Measurements and sync

Provider integration and PR quotas are not yet implemented. All gates are pending.

- [ ] Compare account contribution dates/counts with GitHub's provider calendar.
- [ ] Inspect the exact PR list behind opened and authored-merged counts.
- [ ] Confirm a PR opened earlier and merged today counts once today for merged activity.
- [ ] Username-only: calendar matches the public profile and is labeled unofficial.
- [ ] Token: the account is the token owner; a second token owned by another user shows
      "Belongs to @x, not counted"; repository filters, private access, and revoked token behave.
- [ ] Username to token switch (0.9.0): type username A while a token owned by B is saved
      (or add B's token while A is typed). The app shows @B only, never "Verified for @A",
      and never shows A's counts, quota, or PRs under B (or the reverse) while syncing;
      until B's first sync it says "No data for @B yet".
- [ ] Immediate sync (0.9.0): adding a token, removing a token, and saving a new username
      each start a sync at once, including while a sync is already running (it runs right
      after); token rows show "Checking…" or the remembered owner, not a stale verdict.
- [ ] Several tokens: add an account token and an organization-owned token; private org
      PRs appear once (not duplicated); removing or revoking one names it in the notice and
      marks counts as possibly low. An upgraded install keeps its earlier token as "Personal".
- [ ] Classic token: refused with InsecuSlopometer™ off; accepted and labeled "Classic" when
      on; the toggle cannot be turned off while a classic token is saved.
- [ ] Repository checklist: lists synced repositories ticked by default; unticking one updates
      counts, quota, and widget; the last one cannot be unticked; "All repositories" restores all.
- [ ] Verify missing/partial permissions and pagination never turn unknown activity into zero.
- [ ] Test repeated sync, offline startup, delayed provider updates, and rate-limit backoff.
- [ ] First sync with a token: the calendar and the last 30 days of PRs appear (app, menu
      bar, widget) while the refresh control still reads "Loading older PRs…"; older days
      stay unknown, not zero, until it finishes; no 2-second gaps between search requests.
- [ ] Later syncs: a manual refresh after merging a PR finishes in a few seconds with one
      `updated:` search per token and shows the merge; a PR deleted on GitHub disappears
      only after the daily full reconcile (or a new token, which forces one).
- [ ] Search budget: a sync of more than 28 search requests in a minute waits instead of
      receiving 403/429; with a revoked token mid-sync the other tokens' data is kept.
- [ ] Check local midnight and daylight-saving transitions; document provider-calendar differences.
- [ ] Confirm 7/30-day averages include zero days, warm-up history, and missing-data gaps.
- [ ] Set/edit a quota; exceed it; verify exact scope/unit, day reset, and PR evidence.
- [ ] Quota notification (1.0.0): turning on "Notify when reached" asks for macOS
      permission once; reaching the target shows one "Daily slop quota reached" banner
      after the next sync, with the unit and scope; later syncs, a relaunch, or exceeding
      the target the same day post nothing more; the next day it can fire again.
- [ ] With some PRs possibly missing (a failed token), no notification is posted even
      when the count meets the target. Clicking the banner opens the app window.
- [ ] With notifications denied in System Settings, the caption and "Open Notifications"
      appear, and the button opens Slopometer's notification settings.
- [ ] Verify credentials stay in Keychain and never enter logs, settings, exports, or Git.
- [ ] After a sync with a token, the app container's `Library/Caches/vn.infinitex.slopometer/`
      has no `Cache.db*` or `fsCachedData`, and a launch after a 1.0.0 development build
      removes any that were there (1.0.1).
- [ ] With Keychain refusing a delete (for example a locked keychain), removing a token
      keeps it listed and shows the Keychain notice; a later removal clears it (1.0.1).
- [ ] Verify persisted settings/cache after restart and upgrades without losing source records.
- [ ] Remove All Data (1.0.3), with two tokens (one classic) and the login item, quota
      notification, and widget on: the confirmation states the token count; afterwards
      Keychain Access finds no `vn.infinitex.slopometer.github-token` items; the sheet lists
      both tokens with their kinds and shows both GitHub links (only the fine-grained one
      when no classic token was saved); the widget shows its empty state; Login Items no
      longer lists Slopometer; Quit is the only way out.
- [ ] Relaunch after Remove All Data: the app starts empty (no username, tokens, themes,
      saved configurations, or cached activity) and the Sparkle and login prompts are at
      their first-run defaults. Run once with a sync in progress: the sheet waits, then
      finishes, and the relaunch is still empty.
- [ ] README uninstall fallback: with the app already in the Trash, the `security` command
      deletes the token items one per run and then reports that none are found.

Deterministic numeric/cache tests are separate from this provider checklist.
Record actual account/permission coverage without exposing credential values.
