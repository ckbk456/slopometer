#!/bin/bash
# Installs the pinned XcodeGen release into .build/tools after verifying its checksum.
set -euo pipefail
cd "$(dirname "$0")/.."
version=2.46.0
sha256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
destination=.build/tools/xcodegen
archive="$(mktemp -d)/xcodegen.zip"
curl -fsSL -o "$archive" "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip"
printf '%s  %s\n' "$sha256" "$archive" | shasum -a 256 -c - >/dev/null
rm -rf "$destination"
mkdir -p .build/tools
unzip -q "$archive" -d .build/tools
printf '%s\n' "$PWD/$destination/bin"
