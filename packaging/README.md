# Installer artwork and layout

The DMG carries the download website's Slop Electric palette, Fredoka display
lettering, Bricolage Grotesque text, liquid title and gauge mark. It is static
artwork behind real Finder items, with no installer application or scripts run
on the user's Mac.

- Content area: 720 × 470 points, with toolbar, sidebar, path and status bars hidden.
- Safe area: everything essential, including the install instruction and both icon
  labels, stays above y = 330. Finder keeps the window's outer size, so a person whose
  Finder always shows the tab, path and status bars loses about 125 points of content
  and sees the bottom cropped; the wave band below is decoration only.
- Native icons: 96 points; app centered at (210, 250), Applications at (510, 250).
- Hidden files: `.background.tiff` and `.VolumeIcon.icns` sit below the window at
  y = 620, so showing hidden files in Finder adds a scrollbar instead of covering the art.
- Native filename labels: 14 points, below the icons; not baked into the artwork.
- Background: 720 × 470 and 1440 × 940 PNGs. dmgbuild combines these into a
  multi-resolution TIFF for Finder's standard and Retina rendering.
- The app icon adapts the website's favicon gauge to the macOS inset canvas.
  Its ten macOS representations are in `App/Assets.xcassets/AppIcon.appiconset`;
  `Slopometer.icns` gives the mounted volume the same identity.

## Editing

Edit [the background](artwork/background.svg) or [the icon](artwork/app-icon.svg),
then run `make packaging-art`. This uses uv, Python 3.11+, macOS `iconutil`, and
the hashes/versions in `scripts/render_packaging_art.py.lock`. The bundled
Fontsource 5.3.0 font files match the website; their OFL licenses are beside them.
Text is outlined using those fonts before rasterization, so the result does not
depend on fonts installed on the release machine. Commit the generated PNGs,
icon set and ICNS with their sources. Normal app builds consume those outputs
and do not need uv or the artwork dependencies.

## Packaging

From the repository root, with uv and Python 3.10+:

```sh
make dmg APP=/path/to/Slopometer.app DMG=/new/path/Slopometer.dmg
```

This uses locked dmgbuild 1.6.7 to copy the app unchanged and write the background,
Applications symlink and Finder layout without automating Finder. The output
path must not already exist. For a release, pass the Developer ID export after
notarizing/stapling the app, then sign/notarize/staple the resulting DMG.

Packaging verifies identity-signed apps with `codesign --deep --strict` before
copying and again from a read-only mount of the completed image, detaching its
verification mount even if the signature check fails. It deliberately does not
force-hide the app's extension: that would
add `com.apple.FinderInfo` to the signed bundle and break strict verification.
Unsigned/linker-ad-hoc Debug apps are permitted only for local layout review.

Packaging alone does not sign, notarize, publish, or launch anything. See the
[release procedure](../docs/logic/updates.md#releasing) and the
[pending Finder checks](../testing/MANUAL%20TO-DO/desktop-and-appearance.md).
