#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
APP="packaging/Pesty.app"
DMG="packaging/Pesty-$VERSION.dmg"
PROFILE="${DEVELOPER_ID_PROFILE:-packaging/Pesty_DeveloperID.provisionprofile}"

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to a Developer ID Application identity}"
: "${ASC_KEY:?Set ASC_KEY to the App Store Connect API private key path}"
: "${ASC_KEY_ID:?Set ASC_KEY_ID to the App Store Connect API key ID}"
: "${ASC_ISSUER:?Set ASC_ISSUER to the App Store Connect issuer ID}"

[ -d "$APP" ] || { echo "Missing $APP — run build_app.sh first"; exit 1; }
[ -f "$PROFILE" ] || {
    echo "Missing Developer ID provisioning profile at $PROFILE" >&2
    echo "CloudKit releases require a profile authorizing this bundle ID and iCloud container." >&2
    exit 1
}

PROFILE_PLIST="$(mktemp)"
SIGNING_ENTITLEMENTS="$(mktemp)"
SIGNED_ENTITLEMENTS="$(mktemp)"
cleanup() {
    rm -f "$PROFILE_PLIST" "$SIGNING_ENTITLEMENTS" "$SIGNED_ENTITLEMENTS"
}
trap cleanup EXIT

echo "==> Validating Developer ID CloudKit profile"
security cms -D -i "$PROFILE" > "$PROFILE_PLIST"
plutil -extract Entitlements xml1 -o "$SIGNING_ENTITLEMENTS" "$PROFILE_PLIST"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
APP_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST")"
TEAM_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$PROFILE_PLIST")"
CLOUD_ENVIRONMENT="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.icloud-container-environment' "$PROFILE_PLIST")"

[[ -n "$TEAM_IDENTIFIER" ]] || { echo "Provisioning profile has no team identifier." >&2; exit 1; }
EXPECTED_APP_IDENTIFIER="$TEAM_IDENTIFIER.$BUNDLE_ID"
[[ "$APP_IDENTIFIER" == "$EXPECTED_APP_IDENTIFIER" ]] || {
    echo "Provisioning profile app identifier '$APP_IDENTIFIER' does not match '$EXPECTED_APP_IDENTIFIER'." >&2
    exit 1
}
[[ "$CLOUD_ENVIRONMENT" == "Production" ]] || {
    echo "CloudKit release profile must authorize the Production environment, got '$CLOUD_ENVIRONMENT'." >&2
    exit 1
}

/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.icloud-container-identifiers' \
    "$PROFILE_PLIST" | grep -Fq 'iCloud.com.greycorelabs.pesty' || {
        echo "Provisioning profile does not authorize iCloud.com.greycorelabs.pesty." >&2
        exit 1
    }
/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.icloud-services' \
    "$PROFILE_PLIST" | grep -Fq 'CloudKit' || {
        echo "Provisioning profile does not authorize CloudKit." >&2
        exit 1
    }

cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

echo "==> Codesigning app (hardened runtime)"
codesign --force --options runtime --timestamp \
    --entitlements "$SIGNING_ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP/Contents/MacOS/Pesty"
codesign --force --options runtime --timestamp \
    --entitlements "$SIGNING_ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --entitlements "$SIGNED_ENTITLEMENTS" "$APP" 2>/dev/null

SIGNING_DETAILS="$(codesign --display --verbose=4 "$APP" 2>&1)"
grep -Fq 'Authority=Developer ID Application:' <<< "$SIGNING_DETAILS" || {
    echo "App is not signed with a Developer ID Application certificate." >&2
    exit 1
}
CERT_TEAM_IDENTIFIER="$(awk -F= '$1 == "TeamIdentifier" { print $2; exit }' <<< "$SIGNING_DETAILS")"
[[ "$CERT_TEAM_IDENTIFIER" == "$TEAM_IDENTIFIER" ]] || {
    echo "Signing certificate team '$CERT_TEAM_IDENTIFIER' does not match profile team '$TEAM_IDENTIFIER'." >&2
    exit 1
}

SIGNED_APP_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$SIGNED_ENTITLEMENTS")"
SIGNED_TEAM_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$SIGNED_ENTITLEMENTS")"
[[ "$SIGNED_APP_IDENTIFIER" == "$APP_IDENTIFIER" ]] || {
    echo "Signed application identifier does not match the provisioning profile." >&2
    exit 1
}
[[ "$SIGNED_TEAM_IDENTIFIER" == "$TEAM_IDENTIFIER" ]] || {
    echo "Signed team identifier does not match the provisioning profile." >&2
    exit 1
}
/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.icloud-container-identifiers' \
    "$SIGNED_ENTITLEMENTS" | grep -Fq 'iCloud.com.greycorelabs.pesty' || {
        echo "Final app signature is missing the CloudKit container entitlement." >&2
        exit 1
    }

echo "    app identifier: $SIGNED_APP_IDENTIFIER"
echo "    team identifier: $SIGNED_TEAM_IDENTIFIER"
echo "    CloudKit environment: $CLOUD_ENVIRONMENT"

echo "==> Notarizing app"
ZIP="packaging/Pesty.zip"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" \
    --key "$ASC_KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" \
    --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
rm -f "$ZIP"

echo "==> Building DMG"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/Pesty.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Pesty" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "==> Signing + notarizing DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" \
    --key "$ASC_KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" \
    --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Gatekeeper assessment"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
codesign -dvv "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier" || true

shasum -a 256 "$DMG"
echo "==> Done: $DMG"
