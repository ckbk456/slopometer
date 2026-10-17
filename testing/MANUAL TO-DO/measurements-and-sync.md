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
- [ ] Check local midnight and daylight-saving transitions; document provider-calendar differences.
- [ ] Confirm 7/30-day averages include zero days, warm-up history, and missing-data gaps.
- [ ] Set/edit a quota; exceed it; verify exact scope/unit, day reset, and PR evidence.
- [ ] If enabled, receive one confirmed completion notification per goal/day.
- [ ] Verify credentials stay in Keychain and never enter logs, settings, exports, or Git.
- [ ] Verify persisted settings/cache after restart and upgrades without losing source records.

Deterministic numeric/cache tests are separate from this provider checklist.
Record actual account/permission coverage without exposing credential values.
