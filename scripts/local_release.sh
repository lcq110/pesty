#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    cat <<'EOF'
Usage: ./scripts/local_release.sh [--publish]

Build, Developer ID sign, validate CloudKit entitlements, and notarize locally.
By default the script only creates packaging/Pesty-<version>.dmg.
Use --publish to create the matching GitHub Release after all checks pass.
EOF
}

PUBLISH=false
[[ $# -le 1 ]] || { usage >&2; exit 2; }
case "${1:-}" in
    "") ;;
    --publish) PUBLISH=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

[[ "${GITHUB_ACTIONS:-}" != "true" ]] || {
    echo "Local CloudKit releases cannot run in GitHub Actions." >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || {
    echo "Local releases require macOS." >&2
    exit 1
}

CONFIG_FILE="${LOCAL_RELEASE_CONFIG:-.local-release.env}"
if git ls-files --error-unmatch "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "Refusing to source a tracked local release configuration: $CONFIG_FILE" >&2
    exit 1
fi
if [[ -f "$CONFIG_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    set +a
fi

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY in $CONFIG_FILE or the environment}"
: "${DEVELOPER_ID_PROFILE:?Set DEVELOPER_ID_PROFILE in $CONFIG_FILE or the environment}"
: "${ASC_KEY:?Set ASC_KEY in $CONFIG_FILE or the environment}"
: "${ASC_KEY_ID:?Set ASC_KEY_ID in $CONFIG_FILE or the environment}"
: "${ASC_ISSUER:?Set ASC_ISSUER in $CONFIG_FILE or the environment}"

for local_asset in "$DEVELOPER_ID_PROFILE" "$ASC_KEY"; do
    if git ls-files --error-unmatch "$local_asset" >/dev/null 2>&1; then
        echo "Refusing to use a tracked signing file: $local_asset" >&2
        exit 1
    fi
done

VERSION="${VERSION:-$(tr -d '[:space:]' < .release-version)}"
BUILD="${BUILD:-$(git rev-list --count HEAD)}"
RELEASE_BRANCH="${RELEASE_BRANCH:-codex/ios-companion}"
RELEASE_REPO="${RELEASE_REPO:-lcq110/pesty}"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Invalid release version: $VERSION" >&2
    exit 1
}
[[ "$BUILD" =~ ^[0-9]+$ ]] || {
    echo "BUILD must be an integer, got: $BUILD" >&2
    exit 1
}

CURRENT_BRANCH="$(git branch --show-current)"
[[ "$CURRENT_BRANCH" == "$RELEASE_BRANCH" ]] || {
    echo "Release must be built from $RELEASE_BRANCH; current branch is $CURRENT_BRANCH." >&2
    exit 1
}

WORKTREE_STATUS="$(git status --porcelain --untracked-files=normal)"
[[ -z "$WORKTREE_STATUS" ]] || {
    echo "Release requires a clean worktree:" >&2
    echo "$WORKTREE_STATUS" >&2
    exit 1
}

for command_name in swift security codesign xcrun hdiutil spctl shasum; do
    command -v "$command_name" >/dev/null || {
        echo "Missing required command: $command_name" >&2
        exit 1
    }
done
xcrun --find notarytool >/dev/null

[[ -f "$DEVELOPER_ID_PROFILE" ]] || {
    echo "Developer ID profile not found: $DEVELOPER_ID_PROFILE" >&2
    exit 1
}
[[ -f "$ASC_KEY" ]] || {
    echo "App Store Connect API key not found: $ASC_KEY" >&2
    exit 1
}

AVAILABLE_IDENTITIES="$(security find-identity -p codesigning -v)"
grep -Fq "$SIGN_IDENTITY" <<< "$AVAILABLE_IDENTITIES" || {
    echo "Developer ID identity is not available in the local Keychain:" >&2
    echo "  $SIGN_IDENTITY" >&2
    exit 1
}

export VERSION BUILD SIGN_IDENTITY DEVELOPER_ID_PROFILE ASC_KEY ASC_KEY_ID ASC_ISSUER

echo "==> Local CloudKit release $VERSION ($BUILD)"
echo "    branch: $CURRENT_BRANCH"
echo "    signing assets: local Keychain and local files only"
./scripts/release_build.sh

DMG="packaging/Pesty-$VERSION.dmg"
[[ -f "$DMG" ]] || { echo "Missing release artifact: $DMG" >&2; exit 1; }
SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"

echo "==> Verified local artifact"
echo "    $DMG"
echo "    SHA-256: $SHA256"

if [[ "$PUBLISH" != "true" ]]; then
    echo "==> Not published. Re-run with --publish after inspecting the DMG."
    exit 0
fi

command -v gh >/dev/null || {
    echo "GitHub CLI is required only for --publish." >&2
    exit 1
}
gh auth status --hostname github.com >/dev/null

LOCAL_SHA="$(git rev-parse HEAD)"
git fetch --quiet origin "$RELEASE_BRANCH"
REMOTE_SHA="$(git rev-parse FETCH_HEAD)"
[[ "$LOCAL_SHA" == "$REMOTE_SHA" ]] || {
    echo "Local HEAD $LOCAL_SHA does not match origin/$RELEASE_BRANCH $REMOTE_SHA." >&2
    echo "Push or update the branch before publishing." >&2
    exit 1
}

TAG="v$VERSION"
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists; bump .release-version instead of replacing it." >&2
    exit 1
fi
if gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
    echo "Release $TAG already exists; bump .release-version instead of replacing it." >&2
    exit 1
fi

NOTES_FILE="$(mktemp)"
cleanup() {
    rm -f "$NOTES_FILE"
}
trap cleanup EXIT

{
    echo "Pesty $VERSION is built from the $RELEASE_BRANCH branch."
    echo
    echo "The macOS app was signed and notarized locally. It embeds a matching Developer ID provisioning profile authorizing the production CloudKit container."
    echo
    echo "SHA-256: \`$SHA256\`"
} > "$NOTES_FILE"

gh release create "$TAG" "$DMG" \
    --repo "$RELEASE_REPO" \
    --target "$LOCAL_SHA" \
    --title "Pesty $VERSION" \
    --notes-file "$NOTES_FILE" \
    --latest

echo "==> Published $(gh release view "$TAG" --repo "$RELEASE_REPO" --json url --jq .url)"
