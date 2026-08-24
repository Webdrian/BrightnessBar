#!/bin/bash
# Regenerates Resources/AppIcon.icns from Tools/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

echo "==> Zeichne Icon-Größen"
swift Tools/make-icon.swift "$ICONSET"

echo "==> Baue AppIcon.icns"
mkdir -p Resources
iconutil --convert icns "$ICONSET" --output Resources/AppIcon.icns
rm -rf "$WORK"
echo "==> Fertig: Resources/AppIcon.icns"
