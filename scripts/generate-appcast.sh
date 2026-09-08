#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVES_DIR="${1:-$ROOT_DIR/dist}"
OUTPUT_DIR="${2:-$ROOT_DIR/docs}"
DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX:-https://github.com/DdemiurgeE/WindowManager/releases/download/${GITHUB_REF_NAME:-latest}/}"

[[ -n "${SPARKLE_PRIVATE_KEY:-}" ]] || {
  echo "SPARKLE_PRIVATE_KEY is required to generate a signed appcast" >&2
  exit 2
}
[[ -d "$ARCHIVES_DIR" ]] || { echo "Archive directory not found: $ARCHIVES_DIR" >&2; exit 1; }
mkdir -p "$OUTPUT_DIR"

TOOL="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type f -name generate_appcast -perm -111 2>/dev/null | head -1 || true)"
[[ -x "$TOOL" ]] || {
  echo "Sparkle generate_appcast was not found. Resolve the Xcode package first." >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
cp "$ARCHIVES_DIR"/WindowManager-*.zip "$TMP_DIR/"
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOL" \
  --ed-key-file - \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --full-release-notes-url "https://github.com/DdemiurgeE/WindowManager/releases" \
  "$TMP_DIR"
cp "$TMP_DIR/appcast.xml" "$OUTPUT_DIR/appcast.xml"
plutil -lint "$OUTPUT_DIR/appcast.xml" >/dev/null 2>&1 || true
printf 'Generated signed appcast: %s\n' "$OUTPUT_DIR/appcast.xml"