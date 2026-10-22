"""Closed, mutation-checked inventory of console calls in three restore services.

No app, AX client, notification, saved layout, or live display is accessed.
"""

from collections import Counter
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
paths = {
    name: root / "WindowManager/Services" / name
    for name in ("WindowService.swift", "ScreenMonitorService.swift", "StatusBarService.swift")
}
sources = {name: path.read_text() for name, path in paths.items()}

# Keep the functional-path anchors as well as the sink inventory below.
expected = {
    "WindowService.swift": (
        'print("[WindowRestore] No available display; using saved frame")',
        'print("[WindowRestore] Selected display index \\(resolved.display.index) via \\(resolved.selection)")',
        'status: setWindowFrame(element, frame: frame))',
        'let isKnownReason = message.range(of: pattern, options: .regularExpression) != nil ||',
        'let reason = isKnownReason ? message : "AX frame operation failed"',
        'print("[WindowRestore] \\(reason)")',
    ),
    "ScreenMonitorService.swift": (
        'print("[ScreenMonitor] Auto-applying layout")',
        'print("[ScreenMonitor] Restore finished: \\(restoreResult.windowsRestored)/\\(restoreResult.windowsTotal) windows restored")',
        'print("[RestoreLog] \\(event.timestamp.formatted()) \\(event.status.rawValue): \\(event.windowsRestored)/\\(event.windowsTotal) windows, displays: \\(event.screenConfiguration?.screenIDs.count ?? 0)")',
        'print("Notification authorization error code: \\((error as NSError).code)")',
        'print("Failed to deliver notification, error code: \\((error as NSError).code)")',
    ),
    "StatusBarService.swift": ('print("StatusBarService: Applying layout")',),
}

# Exact single-line print calls and multiplicities: every expression here was
# reviewed. Unknown formats (including multiline prints) fail closed.
allowed_prints = {
    "WindowService.swift": r'''
print("No accessibility permission")
print("Skipping window - outside screen bounds (ax: \(axPosition), screen: \(screenFrame))")
print("Captured window on screen \(screenIndex) [relative=\(relativeFrame)]")
print("No accessibility permission")
print("[WindowRestore] No available display; using saved frame")
print("[WindowRestore] Selected display index \(resolved.display.index) via \(resolved.selection)")
print("[WindowRestore] \(reason)")
''',
    "ScreenMonitorService.swift": r'''
print("[ScreenMonitor] Screen configuration change event received")
print("[ScreenMonitor] Screen configuration unchanged, skipping")
print("[ScreenMonitor] Old display count: \(currentScreenConfiguration?.screenIDs.count ?? 0)")
print("[ScreenMonitor] New display count: \(newConfiguration.screenIDs.count)")
print("[ScreenMonitor] Auto-apply is disabled, skipping")
print("[ScreenMonitor] Auto-apply services are not ready, skipping")
print("[ScreenMonitor] Waiting for stable screen configuration")
print("[ScreenMonitor] Ignoring stale pending restore")
print("[ScreenMonitor] Auto-apply services disappeared, skipping")
print("[ScreenMonitor] Auto-apply disabled during stability wait; skipping")
print("[ScreenMonitor] Stability check: displays=\(latestConfiguration.screenIDs.count), stableReadings=\(nextStableReadings)/\(requiredStableScreenReadings), elapsed=\(String(format: "%.2f", elapsed))s")
print("[ScreenMonitor] Stable screen configuration reached")
print("[ScreenMonitor] Screen stability wait timed out; auto-apply skipped")
print("[ScreenMonitor] Auto-applying layout")
print("[ScreenMonitor] Restore started")
print("[ScreenMonitor] Restore finished: \(restoreResult.windowsRestored)/\(restoreResult.windowsTotal) windows restored")
print("[ScreenMonitor] No matching layout found for current screen configuration")
print("[ScreenMonitor] Cancelled pending restore: new screen configuration event")
print("Notification authorization error code: \((error as NSError).code)")
print("Notification permission not granted")
print("Notification permission denied")
print("Unknown notification authorization status")
print("Failed to deliver notification, error code: \((error as NSError).code)")
print("Current display count: \(currentScreenConfiguration?.screenIDs.count ?? 0)")
print("[RestoreLog] \(event.timestamp.formatted()) \(event.status.rawValue): \(event.windowsRestored)/\(event.windowsTotal) windows, displays: \(event.screenConfiguration?.screenIDs.count ?? 0)")
''',
    "StatusBarService.swift": r'''
print("StatusBarService: applyLayout called")
print("StatusBarService: No layout found in representedObject")
print("StatusBarService: Applying layout")
print("StatusBarService: toggleAutoApply called")
print("StatusBarService: Auto-apply set to \(newValue)")
print("StatusBarService: saveCurrentLayout called")
print("StatusBarService: openMainWindow called")
print("StatusBarService: quitApp called")
''',
}

# The one dynamic String console value is allowed only with this exact filter.
safe_on_error = r'''onError: { message in
                // Engine errors are strings; only known AX reason/code shapes may reach the console.
                let pattern = #"^(position|size) (set|read) AXError -?[0-9]+$"#
                let isKnownReason = message.range(of: pattern, options: .regularExpression) != nil ||
                    message == "position read failed" || message == "size read failed"
                let reason = isKnownReason ? message : "AX frame operation failed"
                print("[WindowRestore] \(reason)")
            }'''


def code_mask(source: str) -> str:
    """Keep code positions, masking Swift comments and quoted text.

    This is deliberately not a Swift parser: interpolation inside a *non-print*
    string and macro-generated sinks are outside this scoped static check.
    """
    masked = list(source)
    index = 0
    state = "code"
    quote_end = '"'
    while index < len(source):
        char = source[index]
        if state == "code":
            if source.startswith("//", index):
                state = "line_comment"
                end = index + 2
            elif source.startswith("/*", index):
                state = "block_comment"
                end = index + 2
            elif char == '"' or (char == '#' and source.startswith('#"', index)):
                quote_end = '"#' if char == '#' else '"'
                state = "string"
                end = index + len(quote_end)
            else:
                index += 1
                continue
        elif state == "line_comment":
            if char == "\n":
                state = "code"
                index += 1
                continue
            end = index + 1
        elif state == "block_comment":
            if source.startswith("*/", index):
                state = "code"
                end = index + 2
            else:
                end = index + 1
        else:
            if char == "\\" and quote_end == '"':
                end = min(index + 2, len(source))
            elif source.startswith(quote_end, index):
                state = "code"
                end = index + len(quote_end)
            else:
                end = index + 1
        for offset in range(index, end):
            if source[offset] != "\n":
                masked[offset] = " "
        index = end
    return "".join(masked)


def check(name: str, source: str) -> None:
    for anchor in expected[name]:
        assert source.count(anchor) == 1, f"{name}: missing/duplicated safe anchor: {anchor}"

    # Scan the whole masked source so whitespace between print and '(' can
    # span lines. Quoted text and comments cannot introduce a candidate.
    actual = []
    for match in re.finditer(r"\bprint\s*\(", code_mask(source)):
        start = source.rfind("\n", 0, match.start()) + 1
        end = source.find("\n", match.start())
        line = source[start:end if end != -1 else len(source)]
        call = line.lstrip()
        assert call.startswith("print("), f"{name}: unreviewed console form: {line.strip()}"
        actual.append(call)
    allowed = Counter(allowed_prints[name].strip().splitlines())
    observed = Counter(actual)
    assert observed == allowed, f"{name}: unreviewed calls: {observed - allowed}; missing: {allowed - observed}"

    if name == "WindowService.swift":
        closures = re.findall(r'onError:\s*\{ message in.*?\n\s*\}', source, re.DOTALL)
        assert closures == [safe_on_error], "WindowService.swift: onError whitelist changed"
        assert 'debugName:' not in source


for name, source in sources.items():
    check(name, source)


def must_reject(name: str, source: str, case: str) -> None:
    try:
        check(name, source)
    except AssertionError:
        return
    raise AssertionError(f"guard accepted {case} in {name}")


# Preserve all anchors while adding new sinks: the previous guard missed these.
for name, field in (
    ("ScreenMonitorService.swift", "event.layoutName"),
    ("WindowService.swift", "windowInfo.appName"),
    ("StatusBarService.swift", "layout.name"),
):
    must_reject(name, sources[name] + f'\nlet leaked = {field}; print("[PrivacyProbe] \\(leaked)")\n', "aliased identifier sink")
    must_reject(name, sources[name] + f'\nprint("[PrivacyProbe] \\({field})")\n', "new interpolated sink")
    must_reject(name, sources[name] + f'\nprint(\n    "[PrivacyProbe] \\({field})"\n)\n', "multiline sink")
    must_reject(name, sources[name] + f'\nlet leaked = {field}\nprint\n("[PrivacyProbe] \\(leaked)")\n', "newline-separated aliased sink")
    check(name, sources[name] + '\n// print("example only")\nlet example = "print(\\"not a sink\\")"\n')
    check(name, sources[name] + '\n// print\n// ("comment only")\nlet example = "print\\n(\\"not a sink\\")"\n')

must_reject("ScreenMonitorService.swift", sources["ScreenMonitorService.swift"] +
            '\nprint("[ScreenMonitor] Auto-applying layout")\n', "duplicated approved sink")

name = "WindowService.swift"
must_reject(name, sources[name].replace(
    'let reason = isKnownReason ? message : "AX frame operation failed"',
    'let reason = isKnownReason ? message : "AX frame operation failed"\n'
    '                let leaked = message; print("[PrivacyProbe] \\(leaked)")', 1,
), "onError aliased string sink")
must_reject(name, sources[name].replace(
    'let reason = isKnownReason ? message : "AX frame operation failed"',
    'let reason = isKnownReason ? message : "AX frame operation failed"\n'
    '                let reason = message', 1,
), "onError reason override")
must_reject(name, sources[name].replace(
    'message == "position read failed" || message == "size read failed"',
    'message == "position read failed" || message == "size read failed" || message == "SENTINEL_WINDOW_SECRET"', 1,
), "onError string allowlist expansion")

# Original negative mutations remain useful for ensuring the functional anchors
# are not removed, but are not a substitute for the anchor-preserving cases.
mutants = (
    ("WindowService.swift", 0, "windowInfo.appName"),
    ("WindowService.swift", 1, "windowInfo.appName"),
    ("WindowService.swift", 4, "debugName"),
    ("ScreenMonitorService.swift", 0, "layoutToApply.name"),
    ("ScreenMonitorService.swift", 1, "restoreResult.summaryDescription"),
    ("ScreenMonitorService.swift", 2, "event.layoutName"),
    ("StatusBarService.swift", 0, "layout.name"),
)
for name, index, field in mutants:
    original = expected[name][index]
    mutated = sources[name].replace(original, f'print("SENTINEL_SECRET: \\({field})")', 1)
    must_reject(name, mutated, f"replaced anchor {index}")

print("Restore console privacy: closed print inventory and mutations passed")
