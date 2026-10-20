# /// script
# requires-python = ">=3.10"
# dependencies = ["dmgbuild==1.6.7"]
# ///
"""Package an already-built app; signing, notarization and publication stay separate."""

import argparse
import plistlib
from pathlib import Path

import dmgbuild

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="Path to the built Slopometer.app")
    parser.add_argument("output", type=Path, help="New .dmg file to create (must not exist)")
    args = parser.parse_args()
    app, output = args.app.resolve(), args.output.absolute()
    if app.name != "Slopometer.app" or not (app / "Contents/Info.plist").is_file():
        parser.error("app must be a built Slopometer.app")
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if info.get("CFBundleIdentifier") != "vn.infinitex.slopometer":
        parser.error("unexpected application bundle identifier")
    if output.suffix != ".dmg" or output.exists() or output.is_symlink():
        parser.error("output must be a new .dmg path; existing files are never overwritten")
    output.parent.mkdir(parents=True, exist_ok=True)
    dmgbuild.build_dmg(str(output), "Slopometer", settings={
        "format": "UDZO",
        "filesystem": "HFS+",
        "files": [str(app)],
        "symlinks": {"Applications": "/Applications"},
        "hide_extensions": ["Slopometer.app"],
        "icon": str(ROOT / "packaging/Slopometer.icns"),
        "background": str(ROOT / "packaging/background.png"),
        "window_rect": ((100, 100), (720, 470)),
        "icon_locations": {"Slopometer.app": (210, 270), "Applications": (510, 270)},
        "icon_size": 96,
        "text_size": 14,
        "label_pos": "bottom",
        "arrange_by": None,
        "default_view": "icon-view",
        "show_status_bar": False,
        "show_tab_view": False,
        "show_toolbar": False,
        "show_pathbar": False,
        "show_sidebar": False,
        "include_icon_view_settings": True,
        "include_list_view_settings": False,
    })
    print(f"Created {output}. Sign, notarize and staple it before distribution.")


if __name__ == "__main__":
    main()
