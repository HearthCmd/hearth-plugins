#!/usr/bin/env bash
#
# Generate the catalog signing keypair.
#
# RUN THIS ON YOUR SIGNING MACHINE, ONCE, AND NOWHERE ELSE.
#
# The private key is the whole security model. Anyone holding it can publish
# a catalog that every hearth binary will install without question. It must
# never exist on the relay server, on a build box, in CI, or in this repo.
# Generate it where it will live, so it never has to travel.
#
# Usage:
#   scripts/keygen.sh [output_dir]
#
# Produces, in output_dir (default: ~/hearth-plugin-signing-keys):
#   hearth-catalog-signing.key   PRIVATE — cold storage, mode 0600
#   hearth-catalog-signing.pub   public   — safe to share
#
# and prints the hex PUBLIC key to paste into hearth-cmd's
# cli/plugin_catalog_verify.go trustedCatalogKeys.

set -euo pipefail

# Defaulting to the current directory would drop a private key into whatever
# tree you happened to be standing in -- most likely this repo. Default to a
# named directory under $HOME instead, so the location is deliberate and
# obvious in a file listing a year from now.
OUT_DIR="${1:-$HOME/hearth-plugin-signing-keys}"
KEY="$OUT_DIR/hearth-catalog-signing.key"
PUB="$OUT_DIR/hearth-catalog-signing.pub"

# macOS ships LibreSSL as /usr/bin/openssl, which does not implement the
# Ed25519 raw sign/verify interface this needs. Find a real OpenSSL 3.x.
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
  cat >&2 <<'EOF'
error: no OpenSSL with Ed25519 support found.

macOS ships LibreSSL, which cannot do this. Install real OpenSSL:

    brew install openssl@3

then re-run. Set OPENSSL=/path/to/openssl to point at a specific build.
EOF
  exit 1
fi

echo "using $SSL ($("$SSL" version))"

if [[ -e "$KEY" ]]; then
  echo "error: $KEY already exists. Refusing to overwrite a signing key." >&2
  echo "If you truly mean to rotate, move the old key aside first — and read" >&2
  echo "the rotation notes in README.md, because rotation is a two-release" >&2
  echo "process, not a swap." >&2
  exit 1
fi

# umask before mkdir so a freshly created key directory is 0700 rather than
# whatever the login shell's default would give it. An existing directory
# keeps its own permissions -- changing them silently would be worse than
# leaving a choice the operator already made.
umask 077
mkdir -p "$OUT_DIR"

"$SSL" genpkey -algorithm ED25519 -out "$KEY"
chmod 600 "$KEY"
"$SSL" pkey -in "$KEY" -pubout -out "$PUB"
chmod 644 "$PUB"

# The pinned form is the raw 32-byte key. In an Ed25519 SubjectPublicKeyInfo
# DER the key is the final 32 bytes, after a fixed 12-byte header.
HEX="$("$SSL" pkey -pubin -in "$PUB" -outform DER | tail -c 32 | xxd -p -c 64)"

cat <<EOF

  PRIVATE KEY  $KEY
               mode 0600. Never commit it, never copy it to a server or a
               build box, never paste it anywhere. Anyone holding this can
               publish a catalog every hearth binary installs without
               question.

  public key   $PUB
               Safe to share.

The hex below is the PUBLIC key — not the private one. It is meant to be
published: it gets compiled into every hearth binary, in a public repo.
Paste it into hearth-cmd, cli/plugin_catalog_verify.go:

    var trustedCatalogKeys = []string{
        "$HEX",
    }

Keep the existing entries when rotating: ship a binary trusting both keys,
let it propagate, and only then drop the old one. See README.md.
EOF
