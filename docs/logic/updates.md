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

## Not yet implemented

There is no release job: archiving with Developer ID, notarization, appcast
generation, and upload to the R2 bucket behind `updates.infinitex.vn` are planned
next (see [ROADMAP](../../ROADMAP.md)). Until a feed is published, "Check for
Updates…" reports that it cannot reach the update server.
