/// Ephemeral UI state owned by WindowService, not by a reconstructed view.
/// Only the revision explicitly dismissed is collapsed; a new result is visible.
struct RestoreDiagnosticsPresentation {
    private(set) var dismissedRevision: Int?

    func isExpanded(for revision: Int) -> Bool { dismissedRevision != revision }

    mutating func hide(_ revision: Int) { dismissedRevision = revision }
    mutating func show() { dismissedRevision = nil }
}
