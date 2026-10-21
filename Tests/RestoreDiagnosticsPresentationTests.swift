@main
struct RestoreDiagnosticsPresentationTests {
    static func main() {
        var state = RestoreDiagnosticsPresentation()
        precondition(state.isExpanded, "initial result is visible")
        state.observe(1)
        state.hide()
        precondition(!state.isExpanded, "dismissal collapses diagnostics")
        state.observe(1)
        state.observe(1)
        precondition(!state.isExpanded, "redraw and repeated appearance do not reopen")
        state.show()
        precondition(state.isExpanded, "explicit reopen shows latest result")
        state.hide()
        state.observe(2)
        precondition(state.isExpanded, "new restore revision reopens diagnostics")
        state.hide()
        state.observe(2)
        precondition(!state.isExpanded, "new revision is consumed only once")
        print("RestoreDiagnosticsPresentationTests: 6 checks passed")
    }
}
