#!/bin/bash
set -euo pipefail

# Nib uses Apple's on-device model, which needs Apple silicon. The check asks the hardware,
# because `uname -m` answers x86_64 in a Rosetta shell on an Apple silicon Mac.
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" != "1" ]]; then
  echo "Nib builds only on a Mac with Apple silicon (arm64). This Mac has an Intel processor." >&2
  exit 1
fi

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build_dir="${1:-"$source_dir/Build"}"
app="$build_dir/Nib.app"
bin="$app/Contents/MacOS"
# Each build starts from an empty bundle. macOS can refuse a change inside an app that exists
# ("Operation not permitted", its App Management protection), and an old bundle can hold files
# that left the project. The old bundle goes to the Trash, so nothing is deleted for good.
if [[ -e "$app" ]]; then
  mv -- "$app" "$HOME/.Trash/Nib-build-$(date +%Y%m%d-%H%M%S)-$$.app"
fi
mkdir -p "$bin" "$app/Contents/Resources"
cp "$source_dir/Info.plist" "$app/Contents/Info.plist"
# The extension travels inside the app, so the setup guide can show its folder.
cp -R "$(dirname "$source_dir")/Browser" "$app/Contents/Resources/Browser"
# The icon file comes from Source/make-icons.sh. A first build without it still works.
if [[ -f "$source_dir/AppIcon.icns" ]]; then cp "$source_dir/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"; fi

xcrun swiftc -O -target arm64-apple-macosx26.0 \
  "$source_dir/ProofEngine.swift" "$source_dir/Proofreader.swift" "$source_dir/Overlay.swift" \
  "$source_dir/Icon.swift" "$source_dir/Editor.swift" "$source_dir/Settings.swift" "$source_dir/Welcome.swift" \
  "$source_dir/BrowserExtension.swift" \
  "$source_dir/Desktop.swift" "$source_dir"/Desktop+*.swift -o "$bin/Nib"
xcrun swiftc -O -target arm64-apple-macosx26.0 \
  "$source_dir/ProofEngine.swift" "$source_dir/Bridge.swift" -o "$bin/NibBridge"
# Ad hoc by default. A real identity keeps the Accessibility permission across rebuilds:
#   NIB_SIGN="Apple Development: you@example.com (TEAMID)" bash Source/build.sh
identity="${NIB_SIGN:--}"
# A real identity also gets the hardened runtime, which notarization needs. An ad hoc build stays as it was.
# The secure timestamp needs Apple's server, so only a Developer ID build, the one that ships, asks for it.
options=()
if [[ "$identity" != "-" ]]; then options+=(--options runtime); fi
if [[ "$identity" == "Developer ID"* ]]; then options+=(--timestamp); fi
# ${options[@]+...} because the bash of macOS treats an empty array as unset under `set -u`.
/usr/bin/codesign --force ${options[@]+"${options[@]}"} --sign "$identity" --identifier com.nib.bridge "$bin/NibBridge"
/usr/bin/codesign --force ${options[@]+"${options[@]}"} --sign "$identity" "$app"
/usr/bin/codesign --verify --deep --strict "$app"
printf '%s\n' "$app"
