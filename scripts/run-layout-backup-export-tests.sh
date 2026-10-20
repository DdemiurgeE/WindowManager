#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build"
mkdir -p "$BUILD_DIR"
xcrun --sdk macosx swiftc \
  "$ROOT/WindowManager/Models/WindowInfo.swift" \
  "$ROOT/WindowManager/Models/Layout.swift" \
  "$ROOT/WindowManager/Services/LayoutImportCodec.swift" \
  "$ROOT/WindowManager/Services/LayoutBackupExporter.swift" \
  "$ROOT/Tests/LayoutBackupExporterTests.swift" \
  -o "$BUILD_DIR/LayoutBackupExporterTests"
"$BUILD_DIR/LayoutBackupExporterTests"
