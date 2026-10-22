#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build"
mkdir -p "$BUILD_DIR"
xcrun --sdk macosx swiftc \
  "$ROOT/WindowManager/Models/RestoreDiagnosticsPresentation.swift" \
  "$ROOT/Tests/RestoreDiagnosticsPresentationTests.swift" \
  -o "$BUILD_DIR/RestoreDiagnosticsPresentationTests"
"$BUILD_DIR/RestoreDiagnosticsPresentationTests"

# Compile real service + SwiftUI view wiring, excluding only the app entry point
# and its Sparkle updater. The synthetic test never launches an app or window.
sources=()
while IFS= read -r file; do
  sources+=("$ROOT/$file")
done < <(cd "$ROOT" && git ls-files 'WindowManager/*.swift' 'WindowManager/**/*.swift' | grep -v -E 'WindowManagerApp.swift|UpdateService.swift')
xcrun --sdk macosx swiftc "${sources[@]}" \
  "$ROOT/Tests/RestoreDiagnosticsRemountTests.swift" \
  -o "$BUILD_DIR/RestoreDiagnosticsRemountTests"
"$BUILD_DIR/RestoreDiagnosticsRemountTests"

# Source-level guard: no persisted legacy consent may feed a clipboard action.
if grep -qE 'includeDetailedRestoreDiagnostics|@AppStorage' "$ROOT/WindowManager/Views/LayoutListView.swift"; then
  echo 'Restore diagnostics must not read legacy persisted consent' >&2
  exit 1
fi
echo 'Legacy persisted consent source guard: passed'
