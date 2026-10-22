"""Static, mutation-checked guard for private identifiers in restore console paths.

No app, AX client, notification, saved layout, or live display is accessed.
"""

from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
paths = {
    name: root / "WindowManager/Services" / name
    for name in ("WindowService.swift", "ScreenMonitorService.swift", "StatusBarService.swift")
}
sources = {name: path.read_text() for name, path in paths.items()}

# These templates intentionally allow only counters, a fixed enum reason and a
# numeric AX code. Exact anchors fail closed if a console format is changed.
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
    "StatusBarService.swift": (
        'print("StatusBarService: Applying layout")',
    ),
}


def check(name: str, source: str) -> None:
    for anchor in expected[name]:
        assert source.count(anchor) == 1, f"{name}: missing/duplicated safe anchor: {anchor}"
    # All console prints in the affected files are checked, not only the known
    # lines. UI models and notification body are intentionally not console logs.
    for line in source.splitlines():
        if "print(" not in line or line.lstrip().startswith("//"):
            continue
        assert not re.search(
            r"\\\([^\n]*\b(?:debugName|layoutName|appName|windowTitle|title|"
            r"summaryDescription|screenIDs(?!\.count)|layoutToApply\.name|layout\.name|"
            r"event\.layoutName|windowInfo\.appName|message|error(?! as NSError\)\.code))\b",
            line,
        ), f"{name}: private/dynamic console interpolation: {line.strip()}"
    if name == "WindowService.swift":
        assert 'let pattern = #"^(position|size) (set|read) AXError -?[0-9]+$"#' in source
        assert 'message == "position read failed" || message == "size read failed"' in source
        assert 'print("[WindowRestore] \\(reason)")' in source
        assert 'debugName:' not in source


for name, source in sources.items():
    check(name, source)

# Synthetic private sentinels model identifiers entering each named path. If
# a future edit interpolates any of them, the guard must fail (not merely pass
# by checking that the current source lacks the sentinel literal).
mutants = (
    ("WindowService.swift", 0, "windowInfo.appName", "SENTINEL_APP_SECRET"),
    ("WindowService.swift", 1, "windowInfo.appName", "SENTINEL_APP_SECRET"),
    ("WindowService.swift", 4, "debugName", "SENTINEL_WINDOW_SECRET"),
    ("ScreenMonitorService.swift", 0, "layoutToApply.name", "SENTINEL_LAYOUT_SECRET"),
    ("ScreenMonitorService.swift", 1, "restoreResult.summaryDescription", "SENTINEL_LAYOUT_SECRET"),
    ("ScreenMonitorService.swift", 2, "event.layoutName", "SENTINEL_LAYOUT_SECRET"),
    ("StatusBarService.swift", 0, "layout.name", "SENTINEL_LAYOUT_SECRET"),
)
for name, anchor_index, field, sentinel in mutants:
    original = expected[name][anchor_index]
    mutated = sources[name].replace(original, f'print("{sentinel}: \\({field})")', 1)
    try:
        check(name, mutated)
    except AssertionError:
        pass
    else:
        raise AssertionError(f"guard failed to reject {sentinel} in {name}")

print("Restore console privacy: static sentinel guard passed")
