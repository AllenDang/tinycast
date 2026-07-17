#!/bin/bash
# Exports the stable "Tinycast Self-Signed" identity (cert + private key) as a base64 PKCS#12
# so CI can sign releases with the SAME identity every build. This is what keeps a user's
# Accessibility (TCC) grant alive across Homebrew updates: TCC pins the grant to the code
# signature's designated requirement, and a stable leaf cert keeps that requirement constant.
# Ad-hoc signing (CI's silent fallback) changes it every build → re-prompt on every update.
#
# Run once locally, then add the two printed values as GitHub Actions secrets on the
# abue-ammar/tinycast repo:
#   SIGNING_P12_BASE64     the base64 blob written to build/signing-cert.p12.base64
#   SIGNING_P12_PASSWORD   the random password printed below
#
# macOS may pop a keychain dialog authorizing the export — approve it.
set -euo pipefail

IDENTITY="Tinycast Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/build"
P12="$OUT_DIR/signing-cert.p12"
P12_B64="$OUT_DIR/signing-cert.p12.base64"

if ! security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✗ Identity '$IDENTITY' not found. Run Packaging/dev-cert.sh first." >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
PASS="$(openssl rand -base64 24)"

echo "▸ Exporting '$IDENTITY' (approve the keychain dialog if prompted)…"
# -t identities exports the code-signing identity (cert + key) from the login keychain.
security export -k "$KEYCHAIN" -t identities -f pkcs12 -P "$PASS" -o "$P12"
base64 < "$P12" | tr -d '\n' > "$P12_B64"
rm -f "$P12"

echo
echo "✓ Wrote $P12_B64"
echo
echo "Add these two GitHub Actions secrets to abue-ammar/tinycast:"
echo "  SIGNING_P12_BASE64   →  contents of $P12_B64"
echo "  SIGNING_P12_PASSWORD →  $PASS"
echo
echo "With gh (authed as the repo owner):"
echo "  gh secret set SIGNING_P12_BASE64   --repo abue-ammar/tinycast < \"$P12_B64\""
echo "  gh secret set SIGNING_P12_PASSWORD --repo abue-ammar/tinycast --body '$PASS'"
echo
echo "Then delete $P12_B64 — it holds your private signing key."
