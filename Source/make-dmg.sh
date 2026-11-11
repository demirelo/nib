#!/bin/bash
# Makes the installer: a disk image with Nib.app and a shortcut to the Applications folder.
#   bash Source/make-dmg.sh [build folder]     default build folder: Source/Build
# The result is <build folder>/Nib-<version>.dmg. The user opens it and drags Nib to Applications.
# Signing: NIB_SIGN if it is set, else a "Developer ID Application" identity of this Mac, else ad hoc.
# An "Apple Development" identity is never picked here: the name of that certificate holds the
# developer's email address, and everybody who downloads the image can read it.
# A Developer ID signature alone does not remove the warning on other Macs. For that the image
# must also be notarized by Apple (xcrun notarytool), which this script does not do.
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build_dir="${1:-"$source_dir/Build"}"
mkdir -p "$build_dir"

# Moves a file or folder to the Trash instead of deleting it. Returns an error when the Trash refuses.
trash() {
  if [[ -e "$1" ]]; then mv -- "$1" "$HOME/.Trash/$(basename "$1")-$(date +%Y%m%d-%H%M%S)-$$"; fi
}

# All notes go to stderr: the last line of stdout is the path of the image.
if [[ -n "${NIB_SIGN:-}" ]]; then
  echo "Signing with NIB_SIGN: $NIB_SIGN" >&2
else
  found="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)"
  if [[ -n "$found" ]]; then
    export NIB_SIGN="$found"
    echo "Signing with: $NIB_SIGN" >&2
  else
    export NIB_SIGN="-"
    echo "Signing: ad hoc, because this Mac has no \"Developer ID Application\" identity and NIB_SIGN is not set." >&2
  fi
fi
if [[ "$NIB_SIGN" == "-" ]]; then
  echo "An ad hoc build asks its user for the Accessibility permission again after each update." >&2
fi

app="$(bash "$source_dir/build.sh" "$build_dir" | tail -1)"
bash "$source_dir/test.sh"
version="$(/usr/bin/defaults read "$app/Contents/Info" CFBundleShortVersionString)"
image="$build_dir/Nib-$version.dmg"
stage="$build_dir/dmg"
# Finder writes the path of the draft image into the image itself (in .DS_Store, for the background
# picture). A draft in the build folder would put the builder's user name and folder names into every
# copy of the installer. So the draft lives in a neutral temporary folder.
work="$(/usr/bin/mktemp -d /private/tmp/nib-image.XXXXXX)"
draft="$work/draft.dmg"

# ditto merges into a folder that exists, so files of an older build would stay in the image.
trash "$stage"
mkdir -p "$stage/.background"
/usr/bin/ditto "$app" "$stage/Nib.app"
ln -sfn /Applications "$stage/Applications"
# A link file that opens System Settings at Privacy & Security, where the user allows the first launch.
# The steps in the window point to it. Text in the background picture cannot be clicked, a file can.
/bin/cat > "$stage/Privacy & Security.inetloc" <<'LINK'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>URL</key>
	<string>x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Security</string>
</dict>
</plist>
LINK
"$app/Contents/MacOS/Nib" --icons "$build_dir/icons"
cp "$build_dir/icons/dmg-background.png" "$stage/.background/background.png"

/usr/bin/hdiutil create -quiet -ov -volname Nib -srcfolder "$stage" -fs HFS+ -format UDRW "$draft"
# The draft is mounted in the work folder, not in /Volumes. The user may have a Nib installer open,
# and a second volume with that name must not disturb it. Finder gets the folder path, not the name.
volume="$work/mount"
mkdir "$volume"
/usr/bin/hdiutil attach "$draft" -quiet -noautoopen -mountpoint "$volume"

# The window is 600 x 520 points plus the title bar, the size of the background picture in Source/Icon.swift.
# Finder stores the window layout inside the image. The window holds the steps for the first launch,
# so an image without the layout is not finished: the script stops.
if ! /usr/bin/osascript - "$volume" >/dev/null <<'SCRIPT'
on run arguments
  set imagePath to (POSIX file (item 1 of arguments)) as alias
  with timeout of 30 seconds
    tell application "Finder"
      -- Not "target": that word is a property of a Finder window.
      set place to item imagePath
      open place
      set shown to container window of place
      set current view of shown to icon view
      set toolbar visible of shown to false
      set statusbar visible of shown to false
      set bounds of shown to {200, 120, 800, 668}
      set options to icon view options of shown
      set arrangement of options to not arranged
      set icon size of options to 96
      set text size of options to 13
      set background picture of options to file ".background:background.png" of place
      set position of item "Nib.app" of place to {170, 190}
      set position of item "Applications" of place to {430, 190}
      set position of item "Privacy & Security.inetloc" of place to {490, 405}
      set extension hidden of item "Privacy & Security.inetloc" of place to true
      update place without registering applications
      delay 1
      close shown
    end tell
  end timeout
end run
SCRIPT
then
  /usr/bin/hdiutil detach "$volume" -quiet || true
  echo "Finder did not set the window layout, so the image would show no install steps." >&2
  echo "Allow this terminal to control Finder (System Settings, Privacy & Security, Automation), then run the script again." >&2
  exit 1
fi

/bin/sync
# This is the volume that this script attached a moment ago, not one of the user.
/usr/bin/hdiutil detach "$volume" -quiet
# The old image and the draft go to the Trash. If the Trash refuses, -ov below still replaces the image.
trash "$image" || echo "Note: could not move the old image to the Trash. It is replaced." >&2
/usr/bin/hdiutil convert "$draft" -quiet -ov -format UDZO -imagekey zlib-level=9 -o "$image"
trash "$draft" || echo "Note: could not move the draft image to the Trash. It stays at $draft." >&2
/usr/bin/hdiutil verify -quiet "$image"

# Last check: the finished image must not hold the home folder or the user name of this Mac.
check="$work/check"
/usr/bin/hdiutil attach "$image" -quiet -noautoopen -readonly -nobrowse -mountpoint "$check"
leaks="$(/usr/bin/grep -r -l -a -F -e "$HOME" -e "Users/$USER" -e "Users:$USER" "$check" 2>/dev/null || true)"
/usr/bin/hdiutil detach "$check" -quiet
if [[ -n "$leaks" ]]; then
  echo "The image holds the home folder or user name of this Mac. It is not safe to publish:" >&2
  echo "$leaks" >&2
  trash "$image" || true
  exit 1
fi
echo "$image"
