# Updates and release identity

Implemented in 1.0.0. Slopometer updates itself with
[Sparkle 2](https://sparkle-project.org/documentation/) (pinned to 2.10.0), the
updater most directly distributed Mac apps use.

## Identity

| Item | Value |
| --- | --- |
| App bundle ID | `vn.infinitex.slopometer` |
| Widget bundle ID | `vn.infinitex.slopometer.widget` |
| App Group | `5U4584QFCQ.vn.infinitex.slopometer` |
| Keychain service for tokens | `vn.infinitex.slopometer.github-token` |
| Signing team | `5U4584QFCQ` (Developer ID Application for releases) |
| Update feed | `https://updates.infinitex.vn/slopometer/appcast.xml` |

Builds before 1.0.0 used `dev.slopometer.app`. macOS keeps preferences, the cache,
the App Group container, and Keychain items per identity, so 1.0.0 starts empty: the
username and tokens must be entered again. There is no migration; only development
builds ever used the old identity. Changing any value above after a public release
would strand every installed copy's data and widgets.

## Where releases live

One Cloudflare R2 bucket behind `updates.infinitex.vn` holds everything a release
publishes, under `/slopometer/`:

| Path | Purpose |
| --- | --- |
| `appcast.xml` | Sparkle feed listing every release |
| `Slopometer-<version>.zip` | Signed, notarized update archive for Sparkle |
| `Slopometer.dmg` | Latest notarized disk image; the download site's button links here |

The download site (`ckbk456/slopometer-site`, intended for `slopometer.infinitex.vn`)
hosts neither the feed nor the DMG; its release gate waits for `Slopometer.dmg` to exist
here. A GitHub release may mirror the DMG, but nothing depends on it.

## How an update arrives

`App/Updater.swift` starts Sparkle's standard updater at launch. Sparkle downloads the
appcast (a static XML file listing each release, its archive URL, release notes, and
an EdDSA signature), compares versions using `CFBundleVersion`, and shows its own
update alert. Before installing it checks that the archive's signature matches
`SUPublicEDKey` in `App/Info.plist` and validates the new app's code signature.
The sandboxed app installs through Sparkle's installer XPC service
(`SUEnableInstallerLauncherService` and the `-spks`/`-spki` mach-lookup entitlements);
it already has outgoing network access, so the downloader service stays off.

- **Release builds** check on Sparkle's default schedule (daily) without asking first;
  Settings › Updates › "Check for updates automatically" turns that off.
- **Debug builds** (`make run`, Xcode) default to no scheduled checks, so a published
  release does not offer to replace the build under test. "Check for Updates…" still
  works. Both builds share the bundle ID and preferences, so once the toggle has been
  changed in either build, its saved value applies to both.
- **Gentle reminders:** when a scheduled check finds a release, the app shows a Dock
  icon while Sparkle's alert is up, and the menu bar panel shows "Slopometer x is
  available". Clicking it brings the alert forward. Both clear once the alert is
  looked at or the update session ends.

Nothing installs without the person accepting the alert. The check sends Sparkle's
standard request (app version and macOS version in the user agent); system profile
sending is off.

## Signing key

The EdDSA private key was generated on 2026-10-18 into the release machine's login
Keychain (Sparkle's `generate_keys`, account `ed25519`). It must be backed up
(`generate_keys -x <file>`, kept offline): without it, installed copies cannot accept
any future update. The public key is in `App/Info.plist`. Sparkle's tools are in
`.build/SourcePackages/artifacts/sparkle/Sparkle/bin/` after `make resolve`.

## Releasing

Releases are cut by hand on the release machine; there is no release job yet (see
[ROADMAP](../../ROADMAP.md)). From a clean checkout of merged `main`:

1. Archive Release with `CURRENT_PROJECT_VERSION` set to `git rev-list --count HEAD` and
   `SLOPOMETER_COMMIT` to the short commit, then export with Developer ID (team
   `5U4584QFCQ`). Check that the app, the widget, and Sparkle's helpers carry the
   Developer ID signature and the hardened runtime, and that no `get-task-allow`
   entitlement remains.
2. Notarize the app with `notarytool` (Keychain profile `slopometer-notary`, an App Store
   Connect API key) and staple it.
3. Build `Slopometer.dmg` from the stapled app and an Applications link, sign it with
   Developer ID, then notarize and staple it.
4. Zip the stapled app with `ditto -c -k --sequesterRsrc --keepParent` as
   `Slopometer-<version>.zip`, put the release notes beside it as
   `Slopometer-<version>.html` and the published `appcast.xml` with them, and run
   `generate_appcast --download-url-prefix https://updates.infinitex.vn/slopometer/
   --embed-release-notes` on that folder.
5. Upload to the R2 bucket `slopometer-releases` under `slopometer/`, in this order so the
   feed never names a missing archive: the zip (`Cache-Control: public, max-age=31536000,
   immutable`), then the DMG and `appcast.xml` (both `public, max-age=300`). Download each
   back and compare checksums.
6. Mirror the DMG on a GitHub release tagged `v<version>` at the release commit.

| Version | Build | Commit | Published |
| --- | --- | --- | --- |
| 1.0.1 | 23 | `13a87fd` | 2026-10-20, the first public release |
