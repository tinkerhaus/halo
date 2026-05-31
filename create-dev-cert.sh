#!/bin/bash
# Creates a persistent self-signed code-signing identity so rebuilds keep the
# same signature hash — which means TCC grants (Accessibility, Input Monitoring)
# survive rebuilds. Run once; idempotent.
set -e

CN="Halo Developer"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$CN"; then
    echo "✓ Code-signing identity '$CN' already exists."
    exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/cert.conf" <<EOF
[req]
distinguished_name = req_dn
prompt = no
x509_extensions = v3_req
[req_dn]
CN = $CN
[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$tmpdir/key.pem" -out "$tmpdir/cert.pem" \
    -days 3650 -config "$tmpdir/cert.conf" -extensions v3_req \
    -subj "/CN=$CN" 2>/dev/null

P12_PASS="halo"
openssl pkcs12 -export -out "$tmpdir/cert.p12" \
    -inkey "$tmpdir/key.pem" -in "$tmpdir/cert.pem" \
    -passout "pass:$P12_PASS" \
    -legacy -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg SHA1

security import "$tmpdir/cert.p12" -k "$KEYCHAIN" -P "$P12_PASS" \
    -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "✓ Created code-signing identity: $CN — re-run ./package.sh."
