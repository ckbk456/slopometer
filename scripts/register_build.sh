#!/bin/bash
# Makes this worktree's Debug build the only registered Slopometer, so the widget
# gallery and slopometer:// links use it instead of a build from another checkout.
# Only Launch Services / PlugInKit registrations change; no files are removed.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/.build/xcode/Build/Products/Debug/Slopometer.app"
BUNDLE_ID=dev.slopometer.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

[ -d "$APP" ] || { printf 'No build at %s\n' "$APP" >&2; exit 1; }

"$LSREGISTER" -dump 2>/dev/null \
    | sed -n 's/^path: *\(.*Slopometer\.app\) (0x[0-9a-f]*)$/\1/p' | sort -u \
    | while IFS= read -r other; do
        [ "$other" = "$APP" ] && continue
        id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$other/Contents/Info.plist" 2>/dev/null || true)
        [ -z "$id" ] || [ "$id" = "$BUNDLE_ID" ] || continue
        if pgrep -f "$other/Contents/" >/dev/null; then
            printf 'Still running, quit it first: %s\n' "$other" >&2
            continue
        fi
        pluginkit -r "$other/Contents/PlugIns/SlopometerWidget.appex" 2>/dev/null || true
        "$LSREGISTER" -u "$other" 2>/dev/null || true
        printf 'Unregistered %s\n' "$other"
    done

"$LSREGISTER" -f -R "$APP"
pluginkit -a "$APP/Contents/PlugIns/SlopometerWidget.appex"
