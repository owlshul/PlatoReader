#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: ./release.sh <version> [release_notes]"
  echo "Example: ./release.sh 1.1.0 \"Added CLI providers, Quick Ask, and in-app updates\""
  exit 1
fi

VERSION="${1#v}"
NOTES="${2:-Release v$VERSION}"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PLIST="$DIR/PlatoReader.app/Contents/Info.plist"
DIST_DIR="$DIR/dist"
ZIP_NAME="PlatoReader-v${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

# Update Info.plist version & build number
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
CUR_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST" 2>/dev/null || echo "1")
NEW_BUILD=$((CUR_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PLIST"

# Build & Sign
"$DIR/build.sh"

# Package zip preserving macOS resource forks/signatures
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$DIR/PlatoReader.app" "$ZIP_PATH"

echo "Packaged: $ZIP_PATH"
echo "Publishing GitHub Release v$VERSION..."

gh release create "v$VERSION" "$ZIP_PATH" \
  --title "PlatoReader v$VERSION" \
  --notes "$NOTES"

echo "Published v$VERSION! Existing users on v1.1.0+ can now update directly from inside PlatoReader."
