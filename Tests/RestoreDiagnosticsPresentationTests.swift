@main
struct RestoreDiagnosticsPresentationTests {
    static func main() {
        // Simulate a retained WindowService and two independently constructed views.
        // Each view reads the owner's revision/dismissal rather than copying UI state.
        final class Owner {
            var revision = 1
            var lastRestoreResult = "retained result"
            var presentation = RestoreDiagnosticsPresentation()
        }
        struct ViewModel {
            let owner: Owner
            var isExpanded: Bool { owner.presentation.isExpanded(for: owner.revision) }
            func hide() { owner.presentation.hide(owner.revision) }
            func show() { owner.presentation.show() }
        }
        let owner = Owner()
        let first = ViewModel(owner: owner)
        precondition(first.isExpanded, "initial result is visible")
        first.hide()
        precondition(!first.isExpanded, "dismissal collapses diagnostics")
        let remounted = ViewModel(owner: owner)
        precondition(owner.lastRestoreResult == "retained result" && !remounted.isExpanded,
                     "new view identity with retained result stays collapsed")
        precondition(!ViewModel(owner: owner).isExpanded, "redraw and reappearance stay collapsed")
        remounted.show()
        precondition(ViewModel(owner: owner).isExpanded, "explicit Show works after remount")
        remounted.hide()
        owner.revision += 1
        precondition(ViewModel(owner: owner).isExpanded, "new restore result revision reopens")
        ViewModel(owner: owner).hide()
        precondition(!ViewModel(owner: owner).isExpanded, "new revision can be dismissed")
        print("RestoreDiagnosticsPresentationTests: 7 checks passed")
    }
}
