import Foundation
import CoreGraphics

/// Read-only dependency used by the preview presentation. The production
/// implementation is WindowService.dryRunRestore; tests can supply a fake.
protocol RestorePreviewPlanning {
    func previewPlan(for layout: Layout) -> WindowRestorePlan
}

struct RestorePreviewRow: Identifiable, Equatable {
    let id: UUID
    let appName: String
    let windowTitle: String
    let display: String
    let frame: String
    let result: String
    let confidence: String
    let isSkipped: Bool
}

struct RestorePreviewPresentation: Equatable {
    let layoutName: String
    let rows: [RestorePreviewRow]
    let warning: String?

    init(plan: WindowRestorePlan) {
        layoutName = plan.layoutName
        rows = plan.items.map { item in
            let display = item.chosenDisplay.map { "Display \($0.index + 1)" } ?? "—"
            let frame = item.targetFrame.map {
                "(\(Int($0.origin.x)), \(Int($0.origin.y))) \(Int($0.width))×\(Int($0.height))"
            } ?? "—"
            return RestorePreviewRow(
                id: item.windowID,
                appName: item.appName,
                windowTitle: item.windowTitle.isEmpty ? "Untitled" : item.windowTitle,
                display: display,
                frame: frame,
                result: item.isSkipped ? "Skipped: \(item.reason)" : item.reason,
                confidence: item.confidence.rawValue.capitalized,
                isSkipped: item.isSkipped
            )
        }
        let skipped = plan.items.filter(\.isSkipped)
        warning = skipped.isEmpty ? nil : "\(skipped.count) window(s) cannot be applied safely. Review skipped windows before Apply."
    }
}

struct RestorePreviewModel {
    private let planner: RestorePreviewPlanning

    init(planner: RestorePreviewPlanning) {
        self.planner = planner
    }

    func presentation(for layout: Layout) -> RestorePreviewPresentation {
        RestorePreviewPresentation(plan: planner.previewPlan(for: layout))
    }
}
