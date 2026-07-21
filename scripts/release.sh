#!/usr/bin/env bash
#
# Build the release artifacts for a catalog release.
#
# Produces three files in dist/:
#   index.json       — the signed manifest of the whole catalog
#   index.json.sig   — detached ed25519 signature (phase 1b; stubbed today)
#   catalog.tar.gz   — the plugins/ tree
#
# The hearth CLI fetches index.json first, verifies its signature, then
# fetches catalog.tar.gz and checks every extracted file against the hashes
# in the index. One tarball rather than per-file fetches means verification
# is atomic: there is no window where some files are new and some are old.
#
# Usage:
#   scripts/release.sh <catalog_version>
#   scripts/release.sh 2026.07.21
#
# Then create a GitHub release on that tag and upload all three files from
# dist/ as release assets. The CLI resolves them via
# /releases/latest/download/<name>, which is a plain redirect and does not
# consume GitHub API rate limit.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: scripts/release.sh <catalog_version>" >&2
  exit 1
fi

CATALOG_VERSION="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$REPO_ROOT/dist"

cd "$REPO_ROOT"

rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> building index"
python3 scripts/build-index.py "$CATALOG_VERSION" "$DIST/index.json"

echo "==> building catalog.tar.gz"
# Flags chosen for reproducibility: a fixed mtime, fixed owner, and sorted
# names mean the same tree produces the same bytes. Without them the tarball
# embeds build time and uid, so two builds of identical content differ --
# which would make "did this artifact come from this tree" unanswerable.
tar --sort=name \
    --mtime='UTC 2020-01-01' \
    --owner=0 --group=0 --numeric-owner \
    --format=gnu \
    -czf "$DIST/catalog.tar.gz" \
    plugins

echo "==> signing"
if [[ -x scripts/sign-index.sh ]] && [[ -n "${HEARTH_CATALOG_SIGNING_KEY:-}" ]]; then
  scripts/sign-index.sh "$DIST/index.json" "$DIST/index.json.sig"
else
  echo "    SKIPPED: no signing key configured."
  echo "    Set HEARTH_CATALOG_SIGNING_KEY to the private key path (phase 1b)."
  echo "    Until then the CLI accepts an unsigned catalog only when built"
  echo "    with signature verification disabled -- never in a release build."
fi

echo
echo "artifacts in dist/:"
ls -la "$DIST"
echo
echo "Next: create a GitHub release tagged '$CATALOG_VERSION' and upload"
echo "every file in dist/ as a release asset."
