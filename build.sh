#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_DIR="$DIR/PlatoReader.app"
SRC_DIR="$DIR/src"
CACHE_DIR="$DIR/../.cache"
TMP_DIR="$DIR/../.tmp"

mkdir -p "$CACHE_DIR/clang"
mkdir -p "$TMP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

echo "Compiling PlatoReader native Swift binary..."

TMPDIR="$TMP_DIR" swiftc \
  -O \
  -module-cache-path "$CACHE_DIR" \
  -Xcc -fmodules-cache-path="$CACHE_DIR/clang" \
  -framework Cocoa \
  -framework PDFKit \
  -framework WebKit \
  -framework Carbon \
  -framework ApplicationServices \
  -framework Vision \
  "$SRC_DIR/Config.swift" \
  "$SRC_DIR/UpdateManager.swift" \
  "$SRC_DIR/WebSearchHelper.swift" \
  "$SRC_DIR/AIService.swift" \
  "$SRC_DIR/AccessibilityHelper.swift" \
  "$SRC_DIR/PDFContextHelper.swift" \
  "$SRC_DIR/FloatingPillWindow.swift" \
  "$SRC_DIR/ExplanationPopover.swift" \
  "$SRC_DIR/SettingsWindowController.swift" \
  "$SRC_DIR/HotkeyManager.swift" \
  "$SRC_DIR/MultitouchManager.swift" \
  "$SRC_DIR/main.swift" \
  -o "$APP_DIR/Contents/MacOS/PlatoReader"

chmod +x "$APP_DIR/Contents/MacOS/PlatoReader"

# Sign with a persistent certificate if available so macOS Accessibility permissions survive updates.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -E '"(Developer ID Application|Apple Development|PlatoReader)' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
fi

if [ -n "$SIGN_IDENTITY" ]; then
  echo "Signing PlatoReader.app with identity: $SIGN_IDENTITY"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
else
  echo "Signing PlatoReader.app with ad-hoc signature (note: create a persistent Code Signing cert to preserve Accessibility permission across updates)."
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "Successfully built PlatoReader.app!"
