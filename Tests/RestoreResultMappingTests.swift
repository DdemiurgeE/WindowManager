import Foundation
import CoreGraphics

@inline(__always)
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("RestoreResultMappingTests failed: \(message)") }
}

@main
struct RestoreResultMappingTests {
    static func main() {
        let ids = (0..<5).map { _ in UUID() }
        let windows = ids.map { id in
            WindowInfo(id: id, appName: id.uuidString, windowTitle: "window", frame: .zero, screenIndex: 0)
        }
        let initial = [
            WindowRestoreResult(id: ids[4], appName: "", windowTitle: "", status: .axFailure),
            WindowRestoreResult(id: ids[1], appName: "", windowTitle: "", status: .windowSkipped),
            WindowRestoreResult(id: ids[3], appName: "", windowTitle: "", status: .appNotFound),
            WindowRestoreResult(id: ids[0], appName: "", windowTitle: "", status: .positionSet),
            WindowRestoreResult(id: ids[2], appName: "", windowTitle: "", status: .positionSet)
        ]
        let missing = RestoreResultMapping.retryableMissingIDs(in: windows, results: initial)
        require(missing == Set([ids[1], ids[3]]), "noncontiguous missing IDs use result identity")

        let retry = [
            WindowRestoreResult(id: ids[3], appName: "", windowTitle: "", status: .positionSet),
            WindowRestoreResult(id: ids[1], appName: "", windowTitle: "", status: .windowSkipped)
        ]
        let stillMissing = RestoreResultMapping.retryableMissingIDs(
            in: windows.filter { missing.contains($0.id) }, results: retry
        )
        require(stillMissing == Set([ids[1]]), "reordered mixed retry results map to correct window")

        let result = RestoreResult(layoutName: "test", windowsResults: initial)
        require(result.windowsRestored == 2, "only verified positionSet results count as restored")
        require(result.summaryDescription == "2/5 windows restored", "summary does not optimistically count failures")
        print("RestoreResultMappingTests: 4 checks passed")
    }
}
