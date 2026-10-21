import Foundation
import CoreGraphics

@inline(__always)
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("RestoreResultMappingTests failed: \(message)") }
}

@main
struct RestoreResultMappingTests {
    static func main() {
        let ids = (0..<6).map { _ in UUID() }
        let windows = ids.map { id in
            WindowInfo(id: id, appName: id.uuidString, windowTitle: "window", frame: .zero, screenIndex: 0)
        }
        let initial = [
            WindowRestoreResult(id: ids[4], appName: "", windowTitle: "", status: .axFailure),
            WindowRestoreResult(id: ids[1], appName: "", windowTitle: "", status: .windowSkipped),
            WindowRestoreResult(id: ids[3], appName: "", windowTitle: "", status: .appNotFound),
            WindowRestoreResult(id: ids[0], appName: "", windowTitle: "", status: .positionSet),
            WindowRestoreResult(id: ids[2], appName: "", windowTitle: "", status: .positionSet),
            WindowRestoreResult(id: ids[5], appName: "", windowTitle: "", status: .coordinateUnavailable)
        ]
        let missing = RestoreResultMapping.retryableMissingIDs(in: windows, results: initial)
        require(missing == Set([ids[1], ids[3], ids[5]]), "noncontiguous missing IDs include unavailable coordinates by identity")

        let retry = [
            WindowRestoreResult(id: ids[3], appName: "", windowTitle: "", status: .positionSet),
            WindowRestoreResult(id: ids[1], appName: "", windowTitle: "", status: .windowSkipped),
            WindowRestoreResult(id: ids[5], appName: "", windowTitle: "", status: .coordinateUnavailable)
        ]
        let stillMissing = RestoreResultMapping.retryableMissingIDs(
            in: windows.filter { missing.contains($0.id) }, results: retry
        )
        require(stillMissing == Set([ids[1], ids[5]]), "reordered mixed retry results map to correct window")

        let result = RestoreResult(layoutName: "test", windowsResults: initial)
        require(result.windowsRestored == 2, "only verified positionSet results count as restored")
        require(result.summaryDescription == "2/6 windows restored", "summary does not optimistically count failures")
        require(result.skippedCount == 2 && result.accessibilityFailureCount == 1, "diagnostic counts distinguish missing and AX failures")
        require(result.windowsTotal == 6 && result.clampCount == 0,
                "unavailable coordinates contribute to total but not success, skip, AX failure, or clamp")
        require(result.coordinateUnavailableCount == 1, "mixed result counts unavailable coordinates separately")
        require(result.compactDiagnosticsDescription ==
                "Verified restored: 2 • Missing/skipped: 2 • AX failures: 1 • App clamps: 0 • Coordinates unavailable: 1",
                "mixed compact diagnostics retain all selected counters")
        let mixedCopy = RestoreResultMapping.redactedDiagnostics(for: result, includeWindowDetails: false)
        require(mixedCopy.contains("Coordinates unavailable: 1") && mixedCopy.contains("Skipped or missing: 2") &&
                mixedCopy.contains("Accessibility failures: 1"), "mixed copied summary distinguishes failure categories")
        let unavailableOnly = RestoreResult(layoutName: "test", windowsResults: [initial[5]])
        require(unavailableOnly.windowsTotal == 1 && unavailableOnly.windowsRestored == 0 &&
                unavailableOnly.skippedCount == 0 && unavailableOnly.accessibilityFailureCount == 0 &&
                unavailableOnly.clampCount == 0 && unavailableOnly.coordinateUnavailableCount == 1,
                "unavailable-only result does not inflate other counters")
        require(unavailableOnly.compactDiagnosticsDescription ==
                "Verified restored: 0 • Missing/skipped: 0 • AX failures: 0 • App clamps: 0 • Coordinates unavailable: 1",
                "unavailable-only compact diagnostics name the outcome")
        require(RestoreResultMapping.redactedDiagnostics(for: unavailableOnly, includeWindowDetails: false)
                .contains("Coordinates unavailable: 1"), "unavailable-only copied summary names the outcome")
        let privateResult = RestoreResult(layoutName: "SentinelPrivateLayout", windowsResults: [
            WindowRestoreResult(id: ids[0], appName: "PrivateApp", windowTitle: "PrivateTitle", status: .windowSkipped)
        ])
        let redacted = RestoreResultMapping.redactedDiagnostics(for: privateResult, includeWindowDetails: false)
        require(!redacted.contains("SentinelPrivateLayout") && !redacted.contains("PrivateApp") && !redacted.contains("PrivateTitle"),
                "default diagnostics exclude layout, app and window names")
        require(redacted.contains("Restored: 0/1") && redacted.contains("Skipped or missing: 1"),
                "default diagnostics retain aggregate counts")
        let optedIn = RestoreResultMapping.redactedDiagnostics(for: privateResult, includeWindowDetails: true)
        require(optedIn.contains("SentinelPrivateLayout") && optedIn.contains("PrivateApp") && optedIn.contains("PrivateTitle"),
                "explicit opt-in includes layout, app and window names")
        require(RestoreResultMapping.retryableIDs(in: initial) == Set([ids[1], ids[3], ids[4], ids[5]]), "manual retry includes missing, failed, and unavailable IDs")
        require(RestoreResult.lastUsedPolicyDescription.contains("not proof"), "lastUsed policy is explicit")
        print("RestoreResultMappingTests: 17 checks passed")
    }
}
