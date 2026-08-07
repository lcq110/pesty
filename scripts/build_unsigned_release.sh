#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
APP="packaging/Pesty.app"
DMG="packaging/Pesty-$VERSION.dmg"

VERSION="$VERSION" BUILD="$BUILD" ./scripts/build_app.sh

echo "==> Applying an ad-hoc signature"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Building ad-hoc signed, not-notarized DMG"
rm -f "$DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Pesty.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Pesty" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

shasum -a 256 "$DMG"
echo "==> Done: $DMG"
