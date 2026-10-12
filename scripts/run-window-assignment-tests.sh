#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build"
mkdir -p "$BUILD_DIR"
xcrun --sdk macosx swiftc \
  "$ROOT/WindowManager/Services/WindowAssignment.swift" \
  "$ROOT/Tests/WindowAssignmentTests.swift" \
  -o "$BUILD_DIR/WindowAssignmentTests"
"$BUILD_DIR/WindowAssignmentTests"
