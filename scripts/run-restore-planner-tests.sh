#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build"
mkdir -p "$BUILD_DIR"
xcrun --sdk macosx swiftc \
  "$ROOT/WindowManager/Models/Layout.swift" \
  "$ROOT/WindowManager/Models/WindowInfo.swift" \
  "$ROOT/WindowManager/Services/ScreenResolver.swift" \
  "$ROOT/WindowManager/Services/WindowAssignment.swift" \
  "$ROOT/WindowManager/Services/RestorePlanner.swift" \
  "$ROOT/Tests/RestorePlannerTests.swift" \
  -o "$BUILD_DIR/RestorePlannerTests"
"$BUILD_DIR/RestorePlannerTests"
