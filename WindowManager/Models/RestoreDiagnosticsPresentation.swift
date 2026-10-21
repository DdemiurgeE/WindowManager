/// Ephemeral UI state. A restore revision advances only when WindowService records a result;
/// ordinary view updates and repeated appearances must not undo an explicit dismissal.
struct RestoreDiagnosticsPresentation {
    private(set) var isExpanded = true
    private(set) var observedRevision: Int?

    mutating func observe(_ revision: Int) {
        if let observedRevision, observedRevision != revision {
            isExpanded = true
        }
        observedRevision = revision
    }

    mutating func hide() { isExpanded = false }
    mutating func show() { isExpanded = true }
}
