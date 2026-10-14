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
        print("RestorePlannerTests: all tests passed")
    }
}
