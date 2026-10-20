# Toolchain and version evidence

Inspected for the bootstrap on 2026-10-16. Versions are evidence for this setup,
not a claim that another OS or CI run passed.

| Component | Repository contract | Observed locally |
| --- | --- | --- |
| Deployment target | macOS 14.0+ in package/project | macOS 27.0.1; macOS 14 not runtime-tested |
| Xcode | 16.4+; CI explicitly selects 16.4 | Xcode 27.1, build 27A9275 |
| Swift | Tools 6.1+, language mode 6 | Apple Swift 6.4 |
| XcodeGen | 2.46.0; CI verifies the release archive SHA-256 | 2.46.0 |
| Formatter | swift-format 601.0.0 pinned in `Tools/Package.swift` | Built from source with the selected toolchain |
| GRDB | Exact 7.11.1 and committed resolution pins | Its tagged manifest requires Swift tools 6.1 |
| Sparkle | Exact 2.10.0 (binary framework) in `project.yml`, pinned in `Package.resolved` | App target only; resolved 2026-10-18 |
| Python | 3.9+ standard library for structural checks | 3.14 installation available |
| Make | GNU Make-compatible commands | Apple-provided GNU Make 3.81 |
| Artwork regeneration | Python 3.11+, uv, fonttools 4.67.0 and resvg-py 0.5.0; adjacent script lockfile | Separate from app build; bundled Fontsource 5.3.0 fonts |
| Disk image assembly | Python 3.10+, uv and dmgbuild 1.6.7; adjacent script lockfile | Uses macOS hdiutil/iconutil/tiffutil without Finder automation |

No dependencies or system tools are installed by `make doctor` or `make setup`.
Initial package resolution downloads GRDB source into ignored build caches.
No application credentials are needed for the preview.

If XcodeGen is absent, the checked-in project still builds. For regeneration,
obtain the exact 2.46.0 release or build that tag according to its upstream guide;
review and install deliberately rather than running an unpinned installer.

## Owning sources

- [XcodeGen 2.46.0 specification](https://github.com/yonaskolb/XcodeGen/blob/2.46.0/Docs/ProjectSpec.md).
- [XcodeGen 2.46.0 release](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0).
- [GRDB 7.11.1 manifest](https://github.com/groue/GRDB.swift/blob/v7.11.1/Package.swift)
  and [tagged documentation](https://github.com/groue/GRDB.swift/tree/v7.11.1/Documentation).
- [Apple Swift Charts](https://developer.apple.com/documentation/charts)
  and [AppKit NSWindow](https://developer.apple.com/documentation/appkit/nswindow).
  The selected Xcode SDK and actual build are the version-specific API checks.
- [GitHub contribution API](https://docs.github.com/en/graphql/reference/users)
  and [OAuth guidance](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/best-practices-for-creating-an-oauth-app).
  Provider integration remains planned; recheck guidance when implementing auth.
- [GitHub macOS 15 runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md):
  Xcode 16.4 was listed at `/Applications/Xcode_16.4.app` when inspected.
  Runner images change; the workflow fails rather than silently choosing another Xcode.

Signing uses Apple Development team `5U4584QFCQ` with automatic provisioning for
local signed builds. A Developer ID Application certificate for the same team is in
the release machine's Keychain, and the Sparkle EdDSA signing key was generated there
(see [Updates](logic/updates.md)). The repo does not yet include notarization
credentials or release automation. The license is MIT (`LICENSE`).

- [Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0),
  [sandboxing guide](https://sparkle-project.org/documentation/sandboxing/), and
  [gentle reminders](https://sparkle-project.org/documentation/gentle-reminders/).
