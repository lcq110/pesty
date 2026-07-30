#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Pesty"
BUNDLE_ID="com.greycorelabs.pesty"
DEVICE_NAME="Pesty iPhone 17 Pro"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PESTY_TEMP_ROOT="${TMPDIR:-/tmp}"
DERIVED_DATA="${PESTY_TEMP_ROOT%/}/PestyMobileDerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Pesty.app"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

cd "$ROOT_DIR"
env USER="$(id -un)" LOGNAME="$(id -un)" xcodegen generate --spec project.yml

if ! xcrun simctl list devices available | grep -Fq "$DEVICE_NAME"; then
    RUNTIME_ID="$(
        xcrun simctl list runtimes -j |
        plutil -extract runtimes json -o - - |
        jq -r '[.[] | select(.isAvailable == true and (.name | startswith("iOS ")))][-1].identifier'
    )"
    xcrun simctl create \
        "$DEVICE_NAME" \
        com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
        "$RUNTIME_ID"
fi

xcrun simctl boot "$DEVICE_NAME" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$DEVICE_NAME" -b

xcodebuild \
    -project PestyMobile.xcodeproj \
    -scheme PestyMobile \
    -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
    -derivedDataPath "$DERIVED_DATA" \
    build

xcrun simctl terminate "$DEVICE_NAME" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE_NAME" "$APP_BUNDLE"

case "$MODE" in
    run)
        xcrun simctl launch "$DEVICE_NAME" "$BUNDLE_ID"
        ;;
    --debug|debug)
        xcrun simctl launch --wait-for-debugger "$DEVICE_NAME" "$BUNDLE_ID"
        ;;
    --logs|logs)
        xcrun simctl launch "$DEVICE_NAME" "$BUNDLE_ID"
        xcrun simctl spawn "$DEVICE_NAME" log stream \
            --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        xcrun simctl launch "$DEVICE_NAME" "$BUNDLE_ID"
        xcrun simctl spawn "$DEVICE_NAME" log stream \
            --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify|verify)
        xcrun simctl launch "$DEVICE_NAME" "$BUNDLE_ID"
        xcrun simctl get_app_container "$DEVICE_NAME" "$BUNDLE_ID" app
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac
