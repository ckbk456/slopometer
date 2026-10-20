# /// script
# requires-python = ">=3.11"
# dependencies = ["fonttools[woff]==4.67.0", "resvg-py==0.5.0"]
# ///
"""Render bundled, editable vectors into the DMG background and native app icons."""

import json
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

import resvg_py
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "packaging/artwork"
SVG = "{http://www.w3.org/2000/svg}"
ET.register_namespace("", SVG[1:-1])


def outlined_background():
    """Use the bundled font versions, independent of the release Mac's fonts."""
    tree = ET.parse(ART / "background.svg")
    fonts = {}
    for parent in list(tree.iter()):
        for element in list(parent):
            if element.tag != SVG + "text":
                continue
            name = element.attrib["data-font"]
            weight = float(element.attrib.get("font-weight", 400))
            key = (name, weight)
            if key not in fonts:
                fonts[key] = instantiateVariableFont(
                    TTFont(ROOT / f"packaging/fonts/{name}.woff2"), {"wght": weight}
                )
            font = fonts[key]
            glyphs = font.getGlyphSet()
            cmap = font.getBestCmap()
            scale = float(element.attrib["font-size"]) / font["head"].unitsPerEm
            spacing = float(element.attrib.get("letter-spacing", 0))
            text = element.text or ""
            width = sum(glyphs[cmap[ord(char)]].width * scale for char in text)
            width += spacing * max(0, len(text) - 1)
            x, y = float(element.attrib["x"]), float(element.attrib["y"])
            anchor = element.attrib.get("text-anchor", "start")
            x -= width * {"start": 0, "middle": .5, "end": 1}[anchor]
            pen = SVGPathPen(glyphs)
            for char in text:
                glyph = glyphs[cmap[ord(char)]]
                glyph.draw(TransformPen(pen, (scale, 0, 0, -scale, x, y)))
                x += glyph.width * scale + spacing
            attributes = {
                key: value for key, value in element.attrib.items()
                if key in ("fill", "stroke", "stroke-width", "paint-order")
            }
            attributes["d"] = pen.getCommands()
            replacement = ET.Element(SVG + "path", attributes)
            parent.insert(list(parent).index(element), replacement)
            parent.remove(element)
    return ET.tostring(tree.getroot(), encoding="unicode")


def main():
    background = outlined_background()
    for scale, suffix in ((1, ""), (2, "@2x")):
        (ROOT / f"packaging/background{suffix}.png").write_bytes(
            resvg_py.svg_to_bytes(svg_string=background, width=720 * scale, height=470 * scale)
        )

    source = (ART / "app-icon.svg").read_text()
    asset = ROOT / "App/Assets.xcassets/AppIcon.appiconset"
    asset.mkdir(parents=True, exist_ok=True)
    images = []
    with tempfile.TemporaryDirectory(prefix="slopometer-icon-") as temporary:
        iconset = Path(temporary) / "Slopometer.iconset"
        iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                suffix = "@2x" if scale == 2 else ""
                filename = f"icon_{size}x{size}{suffix}.png"
                png = resvg_py.svg_to_bytes(
                    svg_string=source, width=size * scale, height=size * scale
                )
                (asset / filename).write_bytes(png)
                (iconset / filename).write_bytes(png)
                images.append({
                    "filename": filename, "idiom": "mac", "scale": f"{scale}x",
                    "size": f"{size}x{size}",
                })
        subprocess.run([
            "iconutil", "--convert", "icns", "--output",
            str(ROOT / "packaging/Slopometer.icns"), str(iconset),
        ], check=True)
    (asset / "Contents.json").write_text(json.dumps({
        "images": images, "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    print("Rendered 1x/2x DMG backgrounds, the macOS app icon set, and the volume icon.")


if __name__ == "__main__":
    main()
