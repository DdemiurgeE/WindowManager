import Foundation
import CoreGraphics

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
    print("PASS: \(message)")
}

@main
struct RestorePlanResultMappingTests {
    static func main() {
        let saved = WindowInfo(appName: "Fixture", windowTitle: "Synthetic",
                               frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                               screenIndex: 0, bundleIdentifier: "com.example.fixture", axRole: "AXWindow")
        let current = WindowAssignmentSnapshot(id: "fake:0", bundleID: "com.example.fixture",
                                               appName: "Fixture", title: "Synthetic", role: "AXWindow",
                                               frame: saved.frame)
        let layout = Layout(name: "Fixture", windows: [saved])
        let planner = RestorePlanner()
        let unavailable = planner.plan(layout: layout, current: [current], displays: []).items[0]
        check(unavailable.skipReason == .coordinateUnavailable, "matched identity with no display has coordinateUnavailable reason")
        check(unavailable.isSkipped && unavailable.candidateID == nil && unavailable.targetFrame == nil,
              "unavailable coordinates have no executable candidate or frame")

        var positionSets = 0
        var sizeSets = 0
        func apply(_ item: WindowRestorePlanItem) -> WindowRestoreResult {
            // Mirror restoreLayout's guard: skipped items never reach the fake setters.
            guard item.targetFrame != nil, item.candidateID != nil else {
                return RestorePlanResultMapping.result(forSkipped: item)
            }
            positionSets += 1
            sizeSets += 1
            return WindowRestoreResult(id: item.windowID, appName: item.appName,
                                       windowTitle: item.windowTitle, status: .positionSet)
        }
        let unavailableResult = apply(unavailable)
        check(unavailableResult.id == saved.id && unavailableResult.status == .coordinateUnavailable,
              "final mapped status preserves coordinateUnavailable")
        check(positionSets == 0 && sizeSets == 0, "unavailable coordinates cause no fake AX setters")
        let summary = RestoreResult(layoutName: layout.name, windowsResults: [unavailableResult])
        check(summary.windowsTotal == 1 && summary.windowsRestored == 0 && summary.skippedCount == 0,
              "coordinateUnavailable is neither positionSet nor ordinary skipped")
        check(summary.summaryDescription == "0/1 windows restored", "summary does not count unavailable coordinates")

        let unmatched = planner.plan(layout: layout, current: [], displays: []).items[0]
        check(unmatched.skipReason == .noIdentityMatch, "ordinary no-match retains planner reason")
        let unmatchedResult = apply(unmatched)
        check(unmatchedResult.status == .windowSkipped, "ordinary no-match remains windowSkipped")
        check(positionSets == 0 && sizeSets == 0, "no-match causes no fake AX setters")
        check(RestoreResult(layoutName: layout.name, windowsResults: [unmatchedResult]).skippedCount == 1,
              "ordinary skip remains counted")
        print("RestorePlanResultMappingTests: all tests passed")
    }
}
