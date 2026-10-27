#!/bin/bash
# Makes this worktree's Debug build the only registered Slopometer Dev, so the widget
# gallery and slopometer-dev:// links use it instead of a build from another checkout.
# Debug builds have their own bundle ID, so an installed release is never touched.
# Only Launch Services / PlugInKit registrations change; no files are removed.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/.build/xcode/Build/Products/Debug/Slopometer.app"
BUNDLE_ID=vn.infinitex.slopometer.dev
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

# chronod keeps a widget extension running from whichever build it loaded last, so it can
# render an old widget after the registration changes. Stop only Debug extension
# processes launched from another build (exact PIDs); chronod relaunches the registered
# one. Release widgets have another bundle ID and keep running.
# There is no command to reload WidgetKit timelines; the relaunched widget rereads the
# snapshot, and the app reloads timelines whenever it publishes new data.
WIDGET_EXEC=SlopometerWidget.appex/Contents/MacOS/SlopometerWidget
for pid in $(pgrep -f "$WIDGET_EXEC" || true); do
    cmd=$(ps -o command= -p "$pid" 2>/dev/null || true)
    case "$cmd" in
        "" | "$APP/"*) continue ;;
    esac
    appex="${cmd%%/Contents/MacOS/SlopometerWidget*}"
    id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$appex/Contents/Info.plist" 2>/dev/null || true)
    [ -z "$id" ] || [ "$id" = "$BUNDLE_ID.widget" ] || continue  # deleted builds have no plist
    if kill -TERM "$pid" 2>/dev/null; then
        printf 'Stopped widget %s from another build: %s\n' "$pid" "${cmd%%$WIDGET_EXEC*}"
    fi
done
