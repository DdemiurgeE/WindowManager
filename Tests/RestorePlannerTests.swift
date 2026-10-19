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
        testTwoTargetsAcrossTwoDisplays()
        print("RestorePlannerTests: all tests passed")
    }

    private static func testTwoTargetsAcrossTwoDisplays() {
        // B02: the planner must preserve each saved UUID's candidate, display,
        // and exact frame independently of all three input enumeration orders.
        let primary = DisplaySnapshot(screenID: "primary", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040), scale: 2, index: 0)
        let right = DisplaySnapshot(screenID: "right", frame: CGRect(x: 1920, y: 0, width: 1280, height: 1024),
                                    visibleFrame: CGRect(x: 1920, y: 0, width: 1280, height: 984), scale: 1, index: 1)
        let primaryFrame = CGRect(x: 140, y: 150, width: 700, height: 500)
        let rightFrame = CGRect(x: 2112, y: 205, width: 640, height: 512)
        let onPrimary = WindowInfo(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                   appName: "Editor", windowTitle: "Document", frame: primaryFrame,
                                   screenIndex: 0, relativeFrame: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.5),
                                   screenID: "primary", bundleIdentifier: "com.example.editor", axRole: "AXWindow",
                                   savedDisplayFrame: primary.frame, savedVisibleFrame: primary.visibleFrame, savedScale: primary.scale)
        let onRight = WindowInfo(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                                 appName: "Editor", windowTitle: "Document", frame: rightFrame,
                                 screenIndex: 1, relativeFrame: CGRect(x: 0.15, y: 0.2, width: 0.5, height: 0.5),
                                 screenID: "right", bundleIdentifier: "com.example.editor", axRole: "AXWindow",
                                 savedDisplayFrame: right.frame, savedVisibleFrame: right.visibleFrame, savedScale: right.scale)
        let livePrimary = WindowAssignmentSnapshot(id: "live-primary", bundleID: "com.example.editor", appName: "Editor",
                                                   title: "Document", role: "AXWindow", frame: primaryFrame)
        let liveRight = WindowAssignmentSnapshot(id: "live-right", bundleID: "com.example.editor", appName: "Editor",
                                                 title: "Document", role: "AXWindow", frame: rightFrame)
        let planner = RestorePlanner()
        for targets in [[onPrimary, onRight], [onRight, onPrimary]] {
            for candidates in [[livePrimary, liveRight], [liveRight, livePrimary]] {
                for displays in [[primary, right], [right, primary]] {
                    let items = planner.plan(layout: Layout(name: "Two displays", windows: targets),
                                             current: candidates, displays: displays).items
                    check(items.count == 2, "B02 retains exactly two targets")
                    let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.windowID, $0) })
                    check(byID.count == 2 && byID[onPrimary.id] != nil && byID[onRight.id] != nil,
                          "B02 indexes distinct saved UUIDs")
                    check(byID[onPrimary.id]?.candidateID == "live-primary"
                          && byID[onPrimary.id]?.chosenDisplay?.screenID == "primary"
                          && byID[onPrimary.id]?.chosenDisplay?.index == 0
                          && byID[onPrimary.id]?.targetFrame == primaryFrame
                          && byID[onPrimary.id]?.confidence == .high
                          && byID[onPrimary.id]?.skipReason == nil && byID[onPrimary.id]?.isSkipped == false,
                          "B02 primary target keeps its candidate, display and exact frame")
                    check(byID[onRight.id]?.candidateID == "live-right"
                          && byID[onRight.id]?.chosenDisplay?.screenID == "right"
                          && byID[onRight.id]?.chosenDisplay?.index == 1
                          && byID[onRight.id]?.targetFrame == rightFrame
                          && byID[onRight.id]?.confidence == .high
                          && byID[onRight.id]?.skipReason == nil && byID[onRight.id]?.isSkipped == false,
                          "B02 right target keeps its candidate, display and exact frame")
                    check(byID[onPrimary.id]?.candidateID != byID[onRight.id]?.candidateID,
                          "B02 candidates are one-to-one")
                }
            }
        }

        // The right observation key disappears: its saved center/index cannot
        // select a present screen, so the resolver uses the sole primary display.
        let removed = planner.plan(layout: Layout(name: "Right removed", windows: [onPrimary, onRight]),
                                   current: [livePrimary, liveRight], displays: [primary]).items
        let fallback = Dictionary(uniqueKeysWithValues: removed.map { ($0.windowID, $0) })
        check(removed.count == 2 && fallback[onPrimary.id]?.candidateID == "live-primary"
              && fallback[onPrimary.id]?.chosenDisplay?.screenID == "primary"
              && fallback[onPrimary.id]?.chosenDisplay?.index == 0
              && fallback[onPrimary.id]?.targetFrame == primaryFrame
              && fallback[onPrimary.id]?.confidence == .high
              && fallback[onPrimary.id]?.skipReason == nil && fallback[onPrimary.id]?.isSkipped == false,
              "B02 primary remains exact when right display is removed")
        check(fallback[onRight.id]?.candidateID == "live-right"
              && fallback[onRight.id]?.chosenDisplay?.screenID == "primary"
              && fallback[onRight.id]?.chosenDisplay?.index == 0
              && fallback[onRight.id]?.targetFrame == CGRect(x: 288, y: 216, width: 960, height: 540)
              && fallback[onRight.id]?.confidence == .high
              && fallback[onRight.id]?.skipReason == nil && fallback[onRight.id]?.isSkipped == false,
              "B02 removed right display selects primary and normalizes its frame")
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
