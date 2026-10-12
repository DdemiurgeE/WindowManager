#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build"
mkdir -p "$BUILD_DIR"
xcrun --sdk macosx swiftc \
  "$ROOT/WindowManager/Models/WindowInfo.swift" \
  "$ROOT/WindowManager/Models/RestoreResult.swift" \
  "$ROOT/Tests/RestoreResultMappingTests.swift" \
  -o "$BUILD_DIR/RestoreResultMappingTests"
"$BUILD_DIR/RestoreResultMappingTests"
