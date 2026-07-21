#!/usr/bin/env bash
#
# Sign a built index.json, producing the detached index.json.sig that hearth
# verifies before installing anything.
#
# RUN THIS ON YOUR SIGNING MACHINE — the one holding the private key.
#
# This is deliberately NOT part of release.sh. The build happens wherever the
# repo lives; the signing key lives in cold storage somewhere else. Wiring
# signing into the build would mean copying the key onto the build box, which
# defeats the point of having it in cold storage at all.
#
# The usual flow:
#   1. on the build box:      scripts/release.sh <version>
#   2. copy dist/index.json and dist/catalog.tar.gz to the signing machine
#   3. on the signing machine: scripts/sign-index.sh index.json <key>
#   4. upload index.json, index.json.sig and catalog.tar.gz to the release
#
# Usage:
#   scripts/sign-index.sh <index.json> [private_key] [output.sig]
#
# private_key defaults to $HEARTH_CATALOG_SIGNING_KEY, then to
# ./hearth-catalog-signing.key.

set -euo pipefail

INDEX="${1:-}"
KEY="${2:-${HEARTH_CATALOG_SIGNING_KEY:-./hearth-catalog-signing.key}}"
SIG="${3:-${INDEX}.sig}"

if [[ -z "$INDEX" ]]; then
  echo "Usage: scripts/sign-index.sh <index.json> [private_key] [output.sig]" >&2
  exit 1
fi
if [[ ! -f "$INDEX" ]]; then
  echo "error: no such file: $INDEX" >&2
  exit 1
fi
if [[ ! -f "$KEY" ]]; then
  echo "error: signing key not found: $KEY" >&2
  echo "Set HEARTH_CATALOG_SIGNING_KEY or pass the path as the second argument." >&2
  exit 1
fi

find_openssl() {
  for candidate in \
      "${OPENSSL:-}" \
      /opt/homebrew/opt/openssl@3/bin/openssl \
      /usr/local/opt/openssl@3/bin/openssl \
      "$(command -v openssl 2>/dev/null || true)"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if "$candidate" genpkey -algorithm ED25519 -out /dev/null 2>/dev/null; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

if ! SSL="$(find_openssl)"; then
  echo "error: no OpenSSL with Ed25519 support found (macOS LibreSSL cannot do this)." >&2
  echo "       brew install openssl@3" >&2
  exit 1
fi

# -rawin signs the message itself rather than a pre-computed digest, which is
# what Ed25519 requires and what Go's ed25519.Verify expects on the other end.
"$SSL" pkeyutl -sign -inkey "$KEY" -rawin -in "$INDEX" -out "$SIG"

SIZE=$(wc -c < "$SIG" | tr -d ' ')
if [[ "$SIZE" != "64" ]]; then
  echo "error: signature is $SIZE bytes, expected 64. Wrong key type?" >&2
  rm -f "$SIG"
  exit 1
fi

# Verify what we just produced. A signature that does not check out against
# its own public key is worth catching here, not after it is published and
# every host is refusing to install.
PUB_TMP="$(mktemp)"
trap 'rm -f "$PUB_TMP"' EXIT
"$SSL" pkey -in "$KEY" -pubout -out "$PUB_TMP"
if ! "$SSL" pkeyutl -verify -pubin -inkey "$PUB_TMP" -rawin -in "$INDEX" -sigfile "$SIG" >/dev/null 2>&1; then
  echo "error: the signature just written does not verify. Refusing to ship it." >&2
  rm -f "$SIG"
  exit 1
fi

HEX="$("$SSL" pkey -pubin -in "$PUB_TMP" -outform DER | tail -c 32 | xxd -p -c 64)"

echo "wrote $SIG (64 bytes, verified)"
echo "signed by public key: $HEX"
echo
echo "That hex must appear in hearth-cmd's cli/plugin_catalog_verify.go"
echo "trustedCatalogKeys, or every hearth binary will refuse this catalog."
