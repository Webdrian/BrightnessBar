#!/bin/bash
# Draws the folder mark and, with a path given, applies it to that folder in Finder.
#
#   ./Tools/make-folder-icon.sh                          # dunkle Kachel nach Resources/
#   ./Tools/make-folder-icon.sh dark  "/pfad/zum/ordner" # setzen
#   ./Tools/make-folder-icon.sh app   "/pfad/zum/ordner" # stattdessen das App-Symbol
#   ./Tools/make-folder-icon.sh folder "/pfad/zum/ordner" # blauer Ordner mit Sonne
#
# Wieder entfernen:  rm "<ordner>/Icon"$'\r'
set -euo pipefail
cd "$(dirname "$0")/.."

STYLE="${1:-dark}"
TARGET="${2:-}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p Resources
swiftc -O -framework AppKit Tools/make-folder-icon.swift -o "$WORK/mk"
if [ -n "$TARGET" ]; then
  "$WORK/mk" "$STYLE" "Resources/FolderIcon.png" "$TARGET"
else
  "$WORK/mk" "$STYLE" "Resources/FolderIcon.png"
fi
