import Foundation
import CoreGraphics

private func check(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError("FAIL: \(message)") }
    print("PASS: \(message)")
}

@main
struct RestorePlannerTests {
    static func main() {
        let display = DisplaySnapshot(screenID: "screen-a", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040), scale: 2, index: 0)
        let saved = WindowInfo(appName: "Editor", windowTitle: "Document", frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                               screenIndex: 0, screenID: "screen-a", bundleIdentifier: "com.example.editor",
                               axRole: "AXWindow", savedDisplayFrame: display.frame, savedVisibleFrame: display.visibleFrame, savedScale: 2)
        let current = WindowAssignmentSnapshot(id: "live:0", bundleID: "com.example.editor", appName: "Editor",
                                                title: "Document", role: "AXWindow", frame: saved.frame)
        let layout = Layout(name: "Desk", windows: [saved])
        let plan = RestorePlanner().plan(layout: layout, current: [current], displays: [display])
        check(plan.items.count == 1, "one plan item per saved window")
        check(plan.items[0].candidateID == "live:0", "candidate is deterministic")
        check(plan.items[0].targetFrame == saved.frame, "target frame uses shared screen resolver")
        check(plan.items[0].skipReason == nil, "matched item is not skipped")

        let ambiguous = [
            WindowAssignmentSnapshot(id: "live:1", bundleID: "com.example.editor", appName: "Editor", title: "Document", role: "AXWindow", frame: saved.frame),
            WindowAssignmentSnapshot(id: "live:2", bundleID: "com.example.editor", appName: "Editor", title: "Document", role: "AXWindow", frame: saved.frame)
        ]
        let skipped = RestorePlanner().plan(layout: layout, current: ambiguous, displays: [display]).items[0]
        check(skipped.skipReason == .ambiguousCandidates, "ambiguous candidate is safely skipped")
        check(skipped.candidateID == nil && skipped.targetFrame == nil, "skipped item has no executable target")

        let validID = saved.id
        let unreadable = WindowInfo(appName: "Editor", windowTitle: "Other", frame: saved.frame,
                                    screenIndex: 0, screenID: "screen-a", bundleIdentifier: "com.example.editor",
                                    axRole: "AXWindow", savedDisplayFrame: display.frame, savedVisibleFrame: display.visibleFrame, savedScale: 2)
        let unreadableID = unreadable.id
        let mixedPlan = RestorePlanner().plan(layout: Layout(name: "Mixed", windows: [saved, unreadable]),
                                              current: [current], displays: [display])
        let scoped = RestorePlanAXFailureScope.idsToMark(plan: mixedPlan,
                                                          targetIDs: [validID, unreadableID])
        check(!scoped.contains(validID), "unreadable peer does not suppress valid planner match")
        check(scoped.contains(unreadableID), "unreadable unmatched target is scoped for AX failure")
        testDuplicateTitlesThroughPlanner(display: display)
        print("RestorePlannerTests: all tests passed")
    }

    private static func testDuplicateTitlesThroughPlanner(display: DisplaySnapshot) {
        // B06: two saved windows with the same identity/title must retain their
        // own candidate and target frame, regardless of enumeration order.
        let near = WindowInfo(appName: "Editor", windowTitle: "Same", frame: CGRect(x: 100, y: 100, width: 400, height: 300),
                              screenIndex: 0, screenID: "screen-a", bundleIdentifier: "com.example.editor", axRole: "AXWindow",
                              savedDisplayFrame: display.frame, savedVisibleFrame: display.visibleFrame, savedScale: 2)
        let far = WindowInfo(appName: "Editor", windowTitle: "Same", frame: CGRect(x: 900, y: 100, width: 400, height: 300),
                             screenIndex: 0, screenID: "screen-a", bundleIdentifier: "com.example.editor", axRole: "AXWindow",
                             savedDisplayFrame: display.frame, savedVisibleFrame: display.visibleFrame, savedScale: 2)
        let liveNear = WindowAssignmentSnapshot(id: "live-near", bundleID: "com.example.editor", appName: "Editor",
                                                title: "Same", role: "AXWindow", frame: near.frame)
        let liveFar = WindowAssignmentSnapshot(id: "live-far", bundleID: "com.example.editor", appName: "Editor",
                                               title: "Same", role: "AXWindow", frame: far.frame)
        let planner = RestorePlanner()
        for targets in [[near, far], [far, near]] {
            for candidates in [[liveNear, liveFar], [liveFar, liveNear]] {
                let items = planner.plan(layout: Layout(name: "Duplicate titles", windows: targets),
                                         current: candidates, displays: [display]).items
                check(items.count == 2, "B06 retains both saved targets")
                let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.windowID, $0) })
                check(byID[near.id]?.candidateID == "live-near" && byID[near.id]?.targetFrame == near.frame
                      && byID[near.id]?.skipReason == nil, "B06 near target maps to near candidate and frame")
                check(byID[far.id]?.candidateID == "live-far" && byID[far.id]?.targetFrame == far.frame
                      && byID[far.id]?.skipReason == nil, "B06 far target maps to far candidate and frame")
            }
        }

        // Equal geometry removes the distinguishing evidence: neither saved
        // target may acquire an executable candidate, including Apply Anyway.
        let tied = WindowAssignmentSnapshot(id: "live-tied", bundleID: "com.example.editor", appName: "Editor",
                                            title: "Same", role: "AXWindow", frame: near.frame)
        let ambiguous = planner.plan(layout: Layout(name: "Duplicate titles", windows: [near, far]),
                                     current: [tied, liveNear], displays: [display]).items
        check(ambiguous.count == 2 && ambiguous.allSatisfy {
            $0.skipReason == .ambiguousCandidates && $0.candidateID == nil && $0.targetFrame == nil
        }, "B06 equal-ranking candidates have no executable target")
    }
}
