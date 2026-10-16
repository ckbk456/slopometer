#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$(uname -s)" != Darwin ]; then
    printf '%s\n' 'Slopometer requires macOS and full Xcode.' >&2
    exit 1
fi
for tool in xcodebuild swift xcrun python3 make git; do
    command -v "$tool" >/dev/null || { printf 'Missing required tool: %s\n' "$tool" >&2; exit 1; }
done
if ! xcodebuild -version >/dev/null 2>&1; then
    printf '%s\n' 'xcodebuild needs full Xcode. Run: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer' >&2
    exit 1
fi
xcodebuild -version
swift --version
python3 --version
if command -v xcodegen >/dev/null; then
    xcodegen --version
else
    printf '%s\n' 'XcodeGen is unavailable. Checked-in project builds work; regeneration needs version 2.46.0.'
fi
printf '%s\n' 'No GitHub credential is required for the sample-data scaffold.'
