#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null; then
    printf '%s\n' 'Install XcodeGen 2.46.0 to regenerate. See docs/TOOLING.md.' >&2
    exit 1
fi
if [ "$(xcodegen --version)" != 'Version: 2.46.0' ]; then
    printf '%s\n' 'Project generation is pinned to XcodeGen 2.46.0. See docs/TOOLING.md.' >&2
    exit 1
fi
xcodegen generate --spec project.yml
