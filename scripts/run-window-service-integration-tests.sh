#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build"
mkdir -p "$BUILD_DIR"
sources=()
while IFS= read -r file; do
  case "$file" in */WindowManagerApp.swift|*/UpdateService.swift|*/PermissionsService.swift) continue;; esac
  sources+=("$ROOT/$file")
done < <(cd "$ROOT" && git ls-files 'WindowManager/*.swift' 'WindowManager/**/*.swift')
# Actual production WindowService/planner/engine, fake AX and permission gate.
# Read-only app/display snapshots only; no real AX, launch or permission writes.
xcrun --sdk macosx swiftc "${sources[@]}" \
  "$ROOT/Tests/Support/FakePermissionsService.swift" \
  "$ROOT/Tests/WindowServiceIntegrationTests.swift" \
  -o "$BUILD_DIR/WindowServiceIntegrationTests"
"$BUILD_DIR/WindowServiceIntegrationTests"
