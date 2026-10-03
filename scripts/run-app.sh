#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
    run|--verify|--debug|--logs|--telemetry) ;;
    *) echo "usage: $0 [run|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/ShipNotes.app"

# Keep development and release builds on the same bundle/resource layout.
pkill -x ShipNotes >/dev/null 2>&1 || true
CONFIG="${CONFIG:-debug}" SIGN_IDENTITY="${SIGN_IDENTITY:--}" "$ROOT_DIR/scripts/build-app.sh"

if [[ "$MODE" == "--debug" ]]; then
    exec lldb -- "$APP_BUNDLE/Contents/MacOS/ShipNotes"
fi

/usr/bin/open -n "$APP_BUNDLE"
case "$MODE" in
    --verify)
        for attempt in 1 2 3 4 5; do
            if pgrep -x ShipNotes >/dev/null; then
                echo "ShipNotes process is running."
                exit 0
            fi
            sleep 1
        done
        echo "ShipNotes did not stay running after launch." >&2
        exit 1
        ;;
    --logs)
        exec /usr/bin/log stream --info --style compact --predicate 'process == "ShipNotes"'
        ;;
    --telemetry)
        exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "org.shipnotes.app"'
        ;;
esac
