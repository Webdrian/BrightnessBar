#!/bin/bash
# Builds BrightnessBar.app next to this script. No Xcode project needed.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="BrightnessBar"
BUNDLE="$APP_NAME.app"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "==> Kompiliere $APP_NAME"
swiftc \
  -O \
  -parse-as-library \
  -target arm64-apple-macos14.0 \
  -framework AppKit -framework SwiftUI -framework IOKit -framework CoreGraphics -framework Carbon \
  -o "$BUNDLE/Contents/MacOS/$APP_NAME" \
  Sources/*.swift

cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
else
  echo "   Hinweis: Resources/AppIcon.icns fehlt — ./Tools/make-icon.sh erzeugt es"
fi

# A stable signing identity matters for more than tidiness: macOS pins the Accessibility
# permission to the code signature. With an ad-hoc signature that pin is the binary's own
# hash, so every rebuild silently invalidates the grant. A self-signed certificate gives a
# designated requirement of "this bundle ID, signed by this certificate", which survives
# rebuilds. Create one with Tools/make-signing-identity.sh; without it, ad-hoc still works.
IDENTITY="BrightnessBar Self-Signed"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "==> Signiere mit \"$IDENTITY\""
  codesign --force --deep --sign "$IDENTITY" "$BUNDLE"
else
  echo "==> Signiere ad-hoc (kein eigenes Zertifikat gefunden)"
  echo "    Hinweis: ./Tools/make-signing-identity.sh erzeugt eines. Ohne es verliert die App"
  echo "    ihre Bedienungshilfen-Freigabe bei jedem Neubau."
  codesign --force --deep --sign - "$BUNDLE"
fi

echo "==> Fertig: $(pwd)/$BUNDLE"

# --install setzt die App nach /Applications. Eine laufende Instanz wird vorher beendet,
# sonst ersetzt man das Bundle unter einem laufenden Prozess.
if [ "${1:-}" = "--install" ]; then
  DEST="/Applications/$BUNDLE"
  echo "==> Installiere nach $DEST"
  pkill -f "$BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true
  sleep 1
  rm -rf "$DEST"
  cp -R "$BUNDLE" "$DEST"
  echo "==> Installiert. Start: open \"$DEST\""
fi
