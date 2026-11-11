#!/bin/bash
# Draws every Nib icon again from Source/Icon.swift. Run it after you change the drawing.
#   bash Source/make-icons.sh
# It writes Browser/icons/nib-*.png and Source/AppIcon.icns. Commit both.
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$source_dir")"
work="$source_dir/Build/icons"

app="$(bash "$source_dir/build.sh" | tail -1)"
mkdir -p "$work"
"$app/Contents/MacOS/Nib" --icons "$work"
/usr/bin/iconutil --convert icns --output "$source_dir/AppIcon.icns" "$work/AppIcon.iconset"
mkdir -p "$root/Browser/icons"
cp "$work"/nib-16.png "$work"/nib-32.png "$work"/nib-48.png "$work"/nib-128.png "$root/Browser/icons/"
echo "Wrote the icons. Preview pictures are in $work"
