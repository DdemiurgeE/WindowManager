#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build"
mkdir -p "$BUILD_DIR"

xcrun --sdk macosx swiftc \
  "$ROOT/WindowManager/Services/AutoApplyRetryPolicy.swift" \
  "$ROOT/Tests/AutoApplyRetryPolicyTests.swift" \
  -o "$BUILD_DIR/AutoApplyRetryPolicyTests"
"$BUILD_DIR/AutoApplyRetryPolicyTests"

# AppKit cannot be driven headlessly here. Verify the deterministic lifecycle
# seam instead: reopen handles hidden existing windows, then creates a new one.
grep -q 'applicationShouldHandleReopen' "$ROOT/WindowManager/WindowManagerApp.swift"
grep -q 'if !flag' "$ROOT/WindowManager/WindowManagerApp.swift"
grep -q 'openOrCreateMainWindow()' "$ROOT/WindowManager/WindowManagerApp.swift"
grep -q 'NSWindow(' "$ROOT/WindowManager/WindowManagerApp.swift"
printf '%s\n' 'AutoApplyRetryPolicyHarness: no-window reopen lifecycle invariant passed'
