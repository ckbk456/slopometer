# /// script
# requires-python = ">=3.10"
# dependencies = ["dmgbuild==1.6.7"]
# ///
"""Package an already-built app; signing, notarization and publication stay separate."""

import argparse
import plistlib
import subprocess
import tempfile
from pathlib import Path

import dmgbuild

ROOT = Path(__file__).resolve().parent.parent


def verify_signed_payload(image):
    """Check the copied bundle, not just the separately signed disk image."""
    with tempfile.TemporaryDirectory(prefix="slopometer-dmg-check-") as temporary:
        mount = Path(temporary) / "mounted"
        mount.mkdir()
        subprocess.run([
            "hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint",
            str(mount), str(image),
        ], check=True)
        try:
            subprocess.run([
                "codesign", "--verify", "--deep", "--strict", "--verbose=2",
                str(mount / "Slopometer.app"),
            ], check=True)
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True)


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
    signature = subprocess.run(
        ["codesign", "--display", "--verbose=2", str(app)], capture_output=True, text=True
    )
    # Unsigned/linker-ad-hoc Debug apps remain useful for local layout review.
    # Any app signed with an identity must pass both before and after copying.
    signed = signature.returncode == 0 and "Authority=" in signature.stderr
    if signed:
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    dmgbuild.build_dmg(str(output), "Slopometer", settings={
        "format": "UDZO",
        "filesystem": "HFS+",
        "files": [str(app)],
        "symlinks": {"Applications": "/Applications"},
        # Do not set hide_extensions: it adds com.apple.FinderInfo to the signed
        # app, which fails codesign --strict even when notarization accepts it.
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
    if signed:
        verify_signed_payload(output)
    else:
        print("Input has no identity signature; this image is for local layout review only.")
    print(f"Created {output}. Sign, notarize and staple it before distribution.")


if __name__ == "__main__":
    main()
