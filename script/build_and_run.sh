#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Pesty"
BUNDLE_ID="com.greycorelabs.pesty"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILT_APP="$ROOT_DIR/packaging/Pesty.app"
RUN_DIR="/tmp/PestyCodexRun"
APP_BUNDLE="$RUN_DIR/Pesty.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
SIGN_IDENTITY="${PESTY_SIGN_IDENTITY:-EasyActions Local Code Signing}"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
VERSION="${VERSION:-1.2.10}" BUILD="${BUILD:-1}" ./scripts/build_app.sh
rm -rf "$APP_BUNDLE"
mkdir -p "$RUN_DIR"
/usr/bin/ditto --norsrc --noextattr "$BUILT_APP" "$APP_BUNDLE"
/usr/bin/xattr -cr "$APP_BUNDLE"
codesign --force --deep --options runtime --timestamp=none \
    --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

open_app() {
    /usr/bin/open -n "$APP_BUNDLE" --args --show
}

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify|verify)
        open_app
        sleep 1
        pgrep -x "$APP_NAME" >/dev/null
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac
