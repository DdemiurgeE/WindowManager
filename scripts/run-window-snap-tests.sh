#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build"
mkdir -p "$BUILD_DIR"
xcrun --sdk macosx swiftc "$ROOT/WindowManager/Services/WindowSnap.swift" \
  "$ROOT/Tests/WindowSnapTests.swift" -o "$BUILD_DIR/WindowSnapTests"
"$BUILD_DIR/WindowSnapTests"
