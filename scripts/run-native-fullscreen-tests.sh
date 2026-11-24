#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build"
mkdir -p "$BUILD_DIR"
# Real service/model/view integration, fake AX only; never run the app.
sources=()
while IFS= read -r file; do
  sources+=("$ROOT/$file")
done < <(cd "$ROOT" && git ls-files 'WindowManager/*.swift' 'WindowManager/**/*.swift' | grep -v -E 'WindowManagerApp.swift|UpdateService.swift')
xcrun --sdk macosx swiftc "${sources[@]}" \
  "$ROOT/Tests/NativeFullscreenTests.swift" \
  -o "$BUILD_DIR/NativeFullscreenTests"
"$BUILD_DIR/NativeFullscreenTests"
