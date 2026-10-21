import AppKit
import Combine
import SwiftUI

// StatusBarService references the app delegate, but this synthetic executable
// never creates an app, window, or AX client operation.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func openOrCreateMainWindow() {}
}

@main
struct RestoreDiagnosticsRemountTests {
    static func main() {
        let service = WindowService()
        var redraws = 0
        let subscription = service.objectWillChange.sink { redraws += 1 }
        defer { subscription.cancel() }
        let layoutID = UUID()
        let initial = RestoreResult(layoutID: layoutID, layoutName: "synthetic", windowsResults: [])
        service.record(initial)

        // Two new view value identities consume the same retained WindowService.
        func mount() -> RestoreDiagnosticsView {
            let result = service.lastRestoreResult!
            return RestoreDiagnosticsView(result: result,
                isExpanded: service.restoreDiagnosticsExpanded,
                includeDetails: .constant(false),
                onToggle: {
                    if service.restoreDiagnosticsExpanded {
                        service.hideRestoreDiagnostics()
                    } else {
                        service.showRestoreDiagnostics()
                    }
                }, onRetry: {})
        }
        let first = mount()
        precondition(first.isExpanded)
        let beforeHide = redraws
        first.onToggle()
        precondition(redraws > beforeHide, "dismissal publishes a redraw to EnvironmentObject views")
        precondition(!mount().isExpanded, "fresh view identity must keep retained result dismissed")
        precondition(!mount().isExpanded, "reappearance and redraw must not reopen")
        let remounted = mount()
        remounted.onToggle()
        precondition(mount().isExpanded, "explicit Show reopens on a new view identity")
        service.hideRestoreDiagnostics()
        service.record(RestoreResult(layoutID: layoutID, layoutName: "new synthetic result", windowsResults: []))
        precondition(mount().isExpanded, "new recorded revision reopens with same owner")
        precondition(mount().result.layoutName == "new synthetic result")
        print("RestoreDiagnosticsRemountTests: 7 checks passed")
    }
}
