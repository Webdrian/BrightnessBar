#!/bin/bash
# Draws the folder icon and, with a path given, applies it to that folder in Finder.
#
#   ./Tools/make-folder-icon.sh                 # nur Resources/FolderIcon.png erzeugen
#   ./Tools/make-folder-icon.sh /pfad/zum/ordner  # zusätzlich auf diesen Ordner setzen
#
# Remove a custom icon again with:  rm "<ordner>/Icon"$'\r'
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p Resources
swiftc -O -framework AppKit Tools/make-folder-icon.swift -o "$WORK/mk"
"$WORK/mk" Resources/FolderIcon.png "${1:--}"
