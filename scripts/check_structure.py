"""Validate repository-local documentation, configuration, and package pins."""

import json
import plistlib
import re
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
REQUIRED = (
    "README.md", "SPEC.md", "SCOPE.md", "ROADMAP.md", "AGENTS.md", "CONTRIBUTING.md",
    "docs/README.md", "docs/DEVELOPMENT.md", "docs/TOOLING.md", "docs/ARCHITECTURE.md",
    "docs/logic/measurements.md", "docs/logic/storage.md", "docs/logic/sync.md",
    "testing/MANUAL TO-DO/README.md",
    "testing/MANUAL TO-DO/desktop-and-appearance.md",
    "testing/MANUAL TO-DO/measurements-and-sync.md",
    ".github/pull_request_template.md", ".github/workflows/ci.yml",
    "Slopometer.xcodeproj/project.pbxproj",
)
errors = []
for relative in REQUIRED:
    path = ROOT / relative
    if not path.is_file() or not path.stat().st_size:
        errors.append(f"Missing or empty required file: {relative}")

for path in ROOT.rglob("*.md"):
    if any(part in {".git", ".build", ".swiftpm"} for part in path.relative_to(ROOT).parts):
        continue
    for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", path.read_text()):
        if target.startswith(("https://", "http://", "mailto:", "#")):
            continue
        relative = unquote(target.strip("<>").split("#", 1)[0])
        destination = (path.parent / relative).resolve()
        if not destination.is_relative_to(ROOT) or not destination.exists():
            errors.append(f"Broken or nonportable link in {path.relative_to(ROOT)}: {target}")

for relative in ("App/Info.plist", "App/Slopometer.entitlements"):
    with (ROOT / relative).open("rb") as handle:
        plistlib.load(handle)
json.loads((ROOT / ".swift-format").read_text())

lock_paths = (
    ROOT / "Package.resolved",
    ROOT / "Slopometer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
)
pins = []
for index, path in enumerate(lock_paths):
    if not path.is_file():
        if index == 0:
            errors.append(f"Missing dependency lockfile: {path.relative_to(ROOT)}")
        continue
    lock = json.loads(path.read_text())
    pins.append([(pin["identity"], pin["state"]) for pin in lock["pins"]])
if len(pins) == 2 and pins[0] != pins[1]:
    errors.append("SwiftPM and Xcode dependency pins disagree")

if errors:
    raise SystemExit("\n".join(errors))
print("Structure, local documentation links, plists, JSON, and dependency pins passed.")
