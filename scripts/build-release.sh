#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ARCH="${ARCH:-$(uname -m)}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/WindowManager-release}"
rm -rf "$OUTPUT_DIR" "$DERIVED_DATA"
mkdir -p "$OUTPUT_DIR"

BUILD_SETTINGS="$(xcodebuild -project WindowManager.xcodeproj -scheme WindowManager -configuration Release -showBuildSettings)"
VERSION="$(printf '%s\n' "$BUILD_SETTINGS" | awk '/^[[:space:]]*MARKETING_VERSION = / {print $3; exit}')"
BUILD="$(printf '%s\n' "$BUILD_SETTINGS" | awk '/^[[:space:]]*CURRENT_PROJECT_VERSION = / {print $3; exit}')"
[[ -n "$VERSION" && -n "$BUILD" ]] || { echo "Cannot determine app version" >&2; exit 1; }

SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}" xcodebuild -project WindowManager.xcodeproj -scheme WindowManager -configuration Release \
  -destination "platform=macOS,arch=$ARCH" -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO build

APP="$DERIVED_DATA/Build/Products/Release/WindowManager.app"
[[ -d "$APP" ]] || { echo "Release app was not built: $APP" >&2; exit 1; }

CLEAN_APP="$OUTPUT_DIR/WindowManager.app"
ditto --noextattr --noqtn "$APP" "$CLEAN_APP"
codesign --verify --deep --strict --verbose=2 "$CLEAN_APP" 2>&1 || true

ZIP="$OUTPUT_DIR/WindowManager-${VERSION}.zip"
(cd "$OUTPUT_DIR" && ditto -c -k --sequesterRsrc --keepParent WindowManager.app "$(basename "$ZIP")")
hdiutil create -volname "WindowManager ${VERSION}" -srcfolder "$CLEAN_APP" -ov -format UDZO "$OUTPUT_DIR/WindowManager-${VERSION}.dmg"

(cd "$OUTPUT_DIR" && shasum -a 256 "WindowManager-${VERSION}.zip" "WindowManager-${VERSION}.dmg" > SHA256SUMS)
rm -rf "$CLEAN_APP"
printf 'Built WindowManager %s (%s) in %s\n' "$VERSION" "$BUILD" "$OUTPUT_DIR"