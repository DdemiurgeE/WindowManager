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
ditto --norsrc --noextattr "$APP" "$CLEAN_APP"
cleanup_xattrs() {
  xattr -cr "$1" 2>/dev/null || true
  find "$1" -print0 | xargs -0 xattr -c 2>/dev/null || true
}

signed=false
for attempt in 1 2 3 4 5; do
  cleanup_xattrs "$CLEAN_APP"
  if codesign --force --deep --sign - "$CLEAN_APP" >/dev/null 2>/tmp/windowmanager-codesign-err.log; then
    signed=true
    break
  fi
  printf 'codesign attempt %s failed, retrying\n' "$attempt" >&2
done
[[ "$signed" == true ]] || { cat /tmp/windowmanager-codesign-err.log >&2; exit 1; }
cleanup_xattrs "$CLEAN_APP"
codesign --verify --deep --verbose=2 "$CLEAN_APP"

ZIP="$OUTPUT_DIR/WindowManager-${VERSION}.zip"
(cd "$OUTPUT_DIR" && ditto -c -k --sequesterRsrc --keepParent WindowManager.app "$(basename "$ZIP")")
hdiutil create -volname "WindowManager ${VERSION}" -srcfolder "$CLEAN_APP" -ov -format UDZO "$OUTPUT_DIR/WindowManager-${VERSION}.dmg"

(cd "$OUTPUT_DIR" && shasum -a 256 "WindowManager-${VERSION}.zip" "WindowManager-${VERSION}.dmg" > SHA256SUMS)
printf 'Built WindowManager %s (%s) in %s\n' "$VERSION" "$BUILD" "$OUTPUT_DIR"