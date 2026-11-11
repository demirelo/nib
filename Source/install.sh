#!/bin/bash
# Builds, tests and installs Nib in one step. It stops at the first failure, so a broken build is never installed.
#   bash Source/install.sh [target folder]     default target: this repository folder
# The target folder receives Nib.app and nothing else.
# Signing: without NIB_SIGN the first "Apple Development" identity of this Mac is used, because a real
# identity keeps the Accessibility permission across builds. Set NIB_SIGN to choose another identity,
# or NIB_SIGN=- for an ad hoc build.
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$source_dir")"
target="${1:-$root}"

# Moves a file or folder to the Trash instead of deleting it.
trash() {
  if [[ -e "$1" ]]; then mv -- "$1" "$HOME/.Trash/$(basename "$1")-$(date +%Y%m%d-%H%M%S)-$$"; fi
}

if [[ -z "${NIB_SIGN:-}" ]]; then
  found="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)"
  if [[ -n "$found" ]]; then export NIB_SIGN="$found"; fi
fi
# To stderr: the last line of stdout from build.sh is the path of the app.
if [[ "${NIB_SIGN:--}" == "-" ]]; then
  echo "Signing: ad hoc. macOS asks for the Accessibility permission again after each build." >&2
else
  echo "Signing with: $NIB_SIGN" >&2
fi
echo "  Set NIB_SIGN=\"<identity>\" to choose another one, or NIB_SIGN=- for an ad hoc build." >&2

# The build folder is reused, so a file that left the project would stay in the app. Start from an empty one.
trash "$source_dir/Build/Nib.app"
app="$(bash "$source_dir/build.sh" | tail -1)"
/usr/bin/codesign --verify --deep --strict "$app"
bash "$source_dir/test.sh"

built="$(/usr/bin/defaults read "$app/Contents/Info" CFBundleShortVersionString)"
/usr/bin/osascript -e 'tell application id "com.nib.desktop" to quit' >/dev/null 2>&1 || true
sleep 1
mkdir -p "$target"
# ditto merges into a folder that exists and would keep old files, so the old app goes to the Trash first.
trash "$target/Nib.app"
/usr/bin/ditto "$app" "$target/Nib.app"
/usr/bin/codesign --verify --deep --strict "$target/Nib.app"
installed="$(/usr/bin/defaults read "$target/Nib.app/Contents/Info" CFBundleShortVersionString)"
[[ "$installed" == "$built" ]] || { echo "Installed version $installed differs from built version $built" >&2; exit 1; }
/usr/bin/open "$target/Nib.app"
echo "Installed Nib $installed in $target"
