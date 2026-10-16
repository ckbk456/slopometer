# Toolchain and version evidence

Inspected for the bootstrap on 2026-10-16. Versions are evidence for this setup,
not a claim that another OS or CI run passed.

| Component | Repository contract | Observed locally |
| --- | --- | --- |
| Deployment target | macOS 14.0+ in package/project | macOS 27.0.1; macOS 14 not runtime-tested |
| Xcode | 16.4+; CI explicitly selects 16.4 | Xcode 27.1, build 27A9275 |
| Swift | Tools 6.1+, language mode 6 | Apple Swift 6.4 |
| XcodeGen | 2.46.0 for regeneration | 2.46.0 |
| Formatter | `xcrun swift-format` bundled with selected Xcode | Version command reports `main`; use recorded Xcode identity |
| GRDB | Exact 7.11.1 and committed resolution pins | Its tagged manifest requires Swift tools 6.1 |
| Python | 3.9+ standard library for structural checks | 3.14 installation available |
| Make | GNU Make-compatible commands | Apple-provided GNU Make 3.81 |

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

The repo does not yet include an updater, signing team, notarization credentials,
production configuration, release automation, or selected license.
