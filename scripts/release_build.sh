#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "CloudKit distribution signing is intentionally local-only." >&2
    echo "Run scripts/local_release.sh on the release Mac instead." >&2
    exit 1
fi

export VERSION="${VERSION:-1.0.0}"
export BUILD="${BUILD:-1}"
bash scripts/build_app.sh
bash scripts/sign_notarize.sh
echo "RELEASE_BUILD_DONE"
