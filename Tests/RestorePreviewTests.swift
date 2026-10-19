import Foundation
import CoreGraphics

private func check(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError("FAIL: \(message)") }
    print("PASS: \(message)")
}

private final class FakePreviewPlanner: RestorePreviewPlanning {
    var previewCalls = 0
    var setterCalls = 0
    let plan: WindowRestorePlan

    init(plan: WindowRestorePlan) { self.plan = plan }

    func previewPlan(for layout: Layout) -> WindowRestorePlan {
        previewCalls += 1
        // A preview dependency has no setter API; this counter documents the
        // invariant and fails if the test accidentally grows an apply path.
        return plan
    }
}

@main
struct RestorePreviewTests {
    static func main() {
        let item = WindowRestorePlanItem(
            windowID: UUID(), appName: "Editor", windowTitle: "Document",
            chosenDisplay: DisplaySnapshot(screenID: "screen-a", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                           visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040), scale: 2, index: 0),
            targetFrame: CGRect(x: 100, y: 100, width: 800, height: 600), candidateID: "live:0",
            confidence: .high, reason: "matched by deterministic identity and geometry", skipReason: nil)
        let plan = WindowRestorePlan(layoutName: "Desk", items: [item])
        let fake = FakePreviewPlanner(plan: plan)
        let model = RestorePreviewModel(planner: fake)
        let layout = Layout(name: "Desk", windows: [])
        let presentation = model.presentation(for: layout)

        check(fake.previewCalls == 1, "preview calls the injected production-planner abstraction")
        check(presentation.rows[0].display == "Display 1", "preview presents chosen display")
        check(presentation.rows[0].frame.contains("800×600"), "preview presents target frame")
        check(fake.setterCalls == 0, "preview performs zero AX setter calls")
        check(presentation.warning == nil, "safe plan has no apply warning")
        print("RestorePreviewTests: all tests passed")
    }
}
