#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build"
mkdir -p "$BUILD_DIR"
xcrun --sdk macosx swiftc \
  "$ROOT/WindowManager/Services/WindowCoordinateConverter.swift" \
  "$ROOT/Tests/WindowCoordinateConverterTests.swift" \
  -o "$BUILD_DIR/WindowCoordinateConverterTests"
"$BUILD_DIR/WindowCoordinateConverterTests"