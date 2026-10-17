# Measurements and sync

Provider integration and PR quotas are not yet implemented. All gates are pending.

- [ ] Compare account contribution dates/counts with GitHub's provider calendar.
- [ ] Inspect the exact PR list behind opened and authored-merged counts.
- [ ] Confirm a PR opened earlier and merged today counts once today for merged activity.
- [ ] Username-only: calendar matches the public profile and is labeled unofficial.
- [ ] Token: mismatched owner is reported; repository filters, private access, and revoked token behave.
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
