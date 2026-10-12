#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build"
mkdir -p "$BUILD_DIR"
xcrun --sdk macosx swiftc \
  "$ROOT/WindowManager/Services/FrameRestoreEngine.swift" \
  "$ROOT/WindowManager/Models/WindowInfo.swift" \
  "$ROOT/WindowManager/Models/RestoreResult.swift" \
  "$ROOT/Tests/FakeAXReadbackTests.swift" \
  -o "$BUILD_DIR/FakeAXReadbackTests"
"$BUILD_DIR/FakeAXReadbackTests"
