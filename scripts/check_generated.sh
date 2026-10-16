#!/bin/bash
# Fails when the committed Xcode project differs from what project.yml generates.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/generate.sh
if ! git diff --quiet -- Slopometer.xcodeproj || [ -n "$(git ls-files --others --exclude-standard Slopometer.xcodeproj)" ]; then
    git status --short -- Slopometer.xcodeproj >&2
    git --no-pager diff -- Slopometer.xcodeproj | head -40 >&2
    printf '%s\n' 'Slopometer.xcodeproj is out of date. Run make generate and commit the result.' >&2
    exit 1
fi
printf '%s\n' 'Generated Xcode project matches project.yml.'
