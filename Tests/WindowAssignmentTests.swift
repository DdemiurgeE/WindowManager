import Foundation
import CoreGraphics

private func window(_ id: String, bundle: String? = "com.example.editor",
                    app: String = "Editor", title: String = "",
                    role: String? = "AXWindow", subrole: String? = nil,
                    x: CGFloat = 0, y: CGFloat = 0) -> WindowAssignmentSnapshot {
    WindowAssignmentSnapshot(id: id, bundleID: bundle, appName: app, title: title,
                   role: role, subrole: subrole,
                   frame: CGRect(x: x, y: y, width: 400, height: 300))
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
    print("PASS: \(message)")
}

@main
struct WindowAssignmentTests {
    static func main() {
        let assigner = WindowAssigner()

        // Exact titles are preferred, independent of current enumeration order.
        do {
            let targets = [window("saved-a", title: "Alpha", x: 0), window("saved-b", title: "Beta", x: 500)]
            let current = [window("live-b", title: "Beta", x: 500), window("live-a", title: "Alpha", x: 0)]
            let result = assigner.assign(targets: targets, current: current)
            check(result == [
                WindowAssignment(targetID: "saved-a", status: .matched(currentID: "live-a")),
                WindowAssignment(targetID: "saved-b", status: .matched(currentID: "live-b"))
            ], "same titles and reordered enumeration")
        }

        // Empty and changed/dynamic titles use identity, role, and unique geometry.
        do {
            let targets = [window("empty", title: "", x: 0), window("dynamic", title: "Report 1", x: 500)]
            let current = [window("new-report", title: "Report 2", x: 500), window("untitled", title: "", x: 0)]
            let result = assigner.assign(targets: targets, current: current)
            check(result == [
                WindowAssignment(targetID: "empty", status: .matched(currentID: "untitled")),
                WindowAssignment(targetID: "dynamic", status: .matched(currentID: "new-report"))
            ], "empty and dynamic titles")
        }

        // A current window may be assigned at most once.
        do {
            let target = window("saved", title: "Only window")
            let result = assigner.assign(targets: [target, target], current: [window("live", title: "Only window")])
            check(result[0].status == .matched(currentID: "live"), "first target receives window")
            check(result[1].status == .skipped(reason: .noIdentityMatch), "duplicate target cannot reuse window")
        }

        // Identical evidence is unsafe: report ambiguity rather than moving either.
        do {
            let target = window("saved", title: "Same", x: 0)
            let current = [window("one", title: "Same", x: 0), window("two", title: "Same", x: 0)]
            let result = assigner.assign(targets: [target], current: current)
            check(result == [WindowAssignment(targetID: "saved", status: .ambiguous(candidateIDs: ["one", "two"]))],
                  "ambiguous candidates are skipped")
        }

        // Old layouts without bundle IDs retain the app-name fallback.
        do {
            let target = window("legacy", bundle: nil, app: "LegacyApp", title: "Document")
            let current = window("live", bundle: nil, app: "LegacyApp", title: "Document")
            check(assigner.assign(targets: [target], current: [current]) ==
                  [WindowAssignment(targetID: "legacy", status: .matched(currentID: "live"))],
                  "legacy appName fallback")

            let wrongBundle = window("wrong", bundle: "com.other.app", app: "LegacyApp", title: "Document")
            check(assigner.assign(targets: [target], current: [wrongBundle]) ==
                  [WindowAssignment(targetID: "legacy", status: .matched(currentID: "wrong"))],
                  "legacy appName fallback tolerates newly captured bundle ID")

            let renamed = window("renamed", bundle: "com.example.editor", app: "Localized Editor", title: "Document")
            let original = window("original", bundle: "com.example.editor", app: "Old Editor", title: "Document")
            check(assigner.assign(targets: [renamed], current: [original]) ==
                  [WindowAssignment(targetID: "renamed", status: .matched(currentID: "original"))],
                  "bundle identity survives localized name change")

            let migrated = window("migrated", bundle: nil, app: "Localized Editor", title: "Document")
            let currentWithBundle = window("current", bundle: "com.example.editor", app: "Localized Editor", title: "Document")
            check(assigner.assign(targets: [migrated], current: [currentWithBundle]) ==
                  [WindowAssignment(targetID: "migrated", status: .matched(currentID: "current"))],
                  "legacy target matches current bundle by app name")

            let sameNameWrongBundle = window("wrong-current", bundle: "com.other.app", app: "Localized Editor", title: "Document")
            check(assigner.assign(targets: [window("strict", bundle: "com.example.editor", app: "Localized Editor", title: "Document")],
                                  current: [sameNameWrongBundle]) ==
                  [WindowAssignment(targetID: "strict", status: .skipped(reason: .noIdentityMatch))],
                  "saved bundle ID remains strict")
        }

        // A flexible target must not steal an exact-title candidate from a
        // constrained target, regardless of enumeration order.
        do {
            let flexible = window("flexible", title: "", x: 0)
            let constrained = window("constrained", title: "Only", x: 500)
            let only = window("only-window", title: "Only", x: 500)
            let other = window("other-window", title: "Other", x: 0)
            let expected = [
                WindowAssignment(targetID: "flexible", status: .matched(currentID: "other-window")),
                WindowAssignment(targetID: "constrained", status: .matched(currentID: "only-window"))
            ]
            check(assigner.assign(targets: [flexible, constrained], current: [only, other]) == expected,
                  "constrained target wins over flexible target")
            check(assigner.assign(targets: [constrained, flexible], current: [other, only]) == [expected[1], expected[0]],
                  "target and candidate reorder invariance")
            let assignedIDs = expected.compactMap { assignment -> String? in
                if case let .matched(id) = assignment.status { return id }
                return nil
            }
            check(Set(assignedIDs).count == assignedIDs.count, "one-to-one assignment has no duplicate IDs")
        }

        print("WindowAssignmentTests: all tests passed")
    }
}
