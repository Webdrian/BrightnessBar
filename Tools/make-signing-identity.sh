#!/bin/bash
# Creates a self-signed code signing certificate in the login keychain.
#
# Why bother: macOS pins the Accessibility permission to the code signature. An ad-hoc
# signature pins the binary's own hash, so every rebuild silently revokes the grant — the
# entry stays visible in System Settings but no longer applies. A certificate makes the
# designated requirement "this bundle ID, signed by this certificate", which survives
# rebuilds. Gatekeeper is unaffected; only the permission becomes stable.
#
# Remove again with:
#   security delete-identity -c "BrightnessBar Self-Signed"
set -euo pipefail

CN="BrightnessBar Self-Signed"

if security find-identity -p codesigning 2>/dev/null | grep -q "$CN"; then
  echo "==> \"$CN\" existiert bereits"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Erzeuge Zertifikat"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -subj "/CN=$CN" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# SHA-1 MAC and 3DES: OpenSSL 3 defaults that macOS's `security` cannot read.
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -passout pass:tempimport -legacy -macalg sha1 \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES 2>/dev/null

echo "==> Importiere in den Anmelde-Schlüsselbund"
security import "$WORK/identity.p12" \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -P tempimport -T /usr/bin/codesign -A

echo "==> Fertig. ./build.sh verwendet das Zertifikat ab jetzt automatisch."
echo "    Die Bedienungshilfen-Freigabe muss einmal neu erteilt werden:"
echo "    tccutil reset Accessibility de.webdrian.brightnessbar"
