# Third-party notices

Slopometer itself is released under the [MIT License](LICENSE). The app bundle
includes the components below; each license file is copied into the app's resources.

## GitHub Octicons

The menu bar uses the original `calendar-16.svg`, `git-pull-request-16.svg`, and
`git-merge-16.svg` from [Primer Octicons](https://github.com/primer/octicons/tree/6dbe38e4e9b4987b2c9332d719c57fbbdd083e2d/icons),
pinned to commit `6dbe38e4e9b4987b2c9332d719c57fbbdd083e2d`.

The unmodified SVG files are bundled in `App/Assets.xcassets` and rendered as
monochrome template images. Copyright (c) 2026 GitHub Inc.; licensed under the
[MIT License](App/Resources/Octicons-LICENSE.txt), also included in the app bundle.

## GRDB.swift

The local cache uses [GRDB.swift](https://github.com/groue/GRDB.swift) 7.11.1,
compiled into the app. Copyright (C) 2015-2025 Gwendal Roué; licensed under the
[MIT License](App/Resources/GRDB-LICENSE.txt).

## Sparkle

In-app updates use [Sparkle](https://github.com/sparkle-project/Sparkle) 2.10.0,
embedded as `Sparkle.framework`. Copyright (c) 2006-2013 Andy Matuschak and other
contributors; licensed under the [MIT License](App/Resources/Sparkle-LICENSE.txt),
which also lists the licenses of the components Sparkle bundles.

## Packaging artwork fonts

The DMG artwork uses Fredoka Variable and Bricolage Grotesque Variable, both from
Fontsource 5.3.0, matching the download website. Their source fonts and SIL Open
Font License texts are in `packaging/fonts/`. They are rendered into the artwork;
the app does not load or install these fonts.
