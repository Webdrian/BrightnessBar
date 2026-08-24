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

echo "==> Signiere ad-hoc"
codesign --force --deep --sign - "$BUNDLE"

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
