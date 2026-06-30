#!/bin/bash
# Creates a stable, self-signed code-signing identity in the login keychain.
#
# Why: ad-hoc signatures (`codesign --sign -`) get a fresh cdhash on every rebuild, so the
# Accessibility (TCC) grant is keyed to a binary that no longer exists — the app then reports
# "permission not given" after each rebuild and has to be re-added. Signing with a *named*
# identity gives a stable designated requirement, so the grant survives rebuilds.
#
# Run once. Then run Packaging/make-app.sh and grant Accessibility a single time.
set -euo pipefail

IDENTITY="Tinycast Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✓ Identity '$IDENTITY' already exists — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

echo "▸ Generating self-signed code-signing certificate…"
# A non-empty password keeps the PKCS#12 MAC compatible with macOS's `security import`
# (empty-password bundles trip "MAC verification failed" on LibreSSL).
P12_PASS="tinycast"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout "pass:$P12_PASS" -name "$IDENTITY" >/dev/null 2>&1

# -A lets codesign use the key without a keychain access prompt on every build.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$P12_PASS" -A -T /usr/bin/codesign >/dev/null

echo "✓ Created '$IDENTITY'."
echo "  Next: Packaging/make-app.sh, then grant Accessibility once — it now persists."
