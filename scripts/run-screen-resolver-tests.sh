#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build"
mkdir -p "$BUILD_DIR"
xcrun --sdk macosx swiftc \
  "$ROOT/WindowManager/Services/ScreenResolver.swift" \
  "$ROOT/Tests/ScreenResolverTests.swift" \
  -o "$BUILD_DIR/ScreenResolverTests"
"$BUILD_DIR/ScreenResolverTests"
