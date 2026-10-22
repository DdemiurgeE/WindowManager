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
            return RestoreDiagnosticsView(result: result, revision: service.restoreResultRevision,
                isExpanded: service.restoreDiagnosticsExpanded,
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

        // Exercise the view's copy actions with a fake sink; no system clipboard or defaults.
        final class FakeClipboard {
            var writes: [String] = []
            var accepts = true
            func write(_ text: String) -> Bool {
                if accepts { writes.append(text) }
                return accepts
            }
        }
        let clipboard = FakeClipboard()
        func privateResult(_ name: String) -> RestoreResult {
            RestoreResult(layoutName: name, windowsResults: [
                WindowRestoreResult(appName: "SentinelPrivateApp", windowTitle: "SentinelPrivateWindow", status: .windowSkipped)
            ])
        }
        func copyView(_ result: RestoreResult, revision: Int = 1,
                      actions: RestoreDiagnosticsCopyActions? = nil) -> RestoreDiagnosticsView {
            RestoreDiagnosticsView(result: result, revision: revision, isExpanded: true,
                onToggle: {}, onRetry: {},
                copyActions: actions ?? RestoreDiagnosticsCopyActions(write: clipboard.write))
        }
        let firstCopy = copyView(privateResult("SentinelPrivateLayout"))
        precondition(firstCopy.copySummary() && clipboard.writes.count == 1)
        precondition(!clipboard.writes[0].contains("SentinelPrivateLayout") &&
            !clipboard.writes[0].contains("SentinelPrivateApp") &&
            !clipboard.writes[0].contains("SentinelPrivateWindow"), "safe action excludes all names")
        firstCopy.requestDetailedCopy()
        precondition(clipboard.writes.count == 1, "request alone never writes")
        firstCopy.cancelDetailedCopy()
        precondition(!firstCopy.confirmDetailedCopy() && clipboard.writes.count == 1, "cancel invalidates confirm")
        firstCopy.requestDetailedCopy()
        precondition(firstCopy.confirmDetailedCopy() && clipboard.writes.count == 2)
        precondition(clipboard.writes[1].contains("SentinelPrivateLayout") &&
            clipboard.writes[1].contains("SentinelPrivateApp") &&
            clipboard.writes[1].contains("SentinelPrivateWindow"), "explicit confirmation writes names once")
        precondition(!firstCopy.confirmDetailedCopy() && clipboard.writes.count == 2, "confirmation consumed")
        precondition(!copyView(privateResult("SentinelPrivateLayout")).confirmDetailedCopy() &&
            clipboard.writes.count == 2, "relaunch-like fresh owner has no remembered consent")
        firstCopy.requestDetailedCopy()
        precondition(clipboard.writes.count == 2, "second named copy also needs confirmation")
        firstCopy.cancelDetailedCopy()
        firstCopy.requestDetailedCopy()
        precondition(!copyView(privateResult("SentinelNewLayout")).confirmDetailedCopy() &&
            clipboard.writes.count == 2, "new result or remount has no inherited consent")
        precondition(!firstCopy.copyActions.confirm(for: privateResult("SentinelNewLayout"), revision: 1) &&
            clipboard.writes.count == 2, "changed result cannot consume old confirmation")
        precondition(!firstCopy.confirmDetailedCopy(), "changed-result attempt consumes old consent")
        clipboard.accepts = false
        precondition(!firstCopy.copySummary() && clipboard.writes.count == 2, "failed sink is not success")
        firstCopy.requestDetailedCopy()
        precondition(!firstCopy.confirmDetailedCopy() && clipboard.writes.count == 2, "failed detailed sink is not success")
        precondition(!firstCopy.confirmDetailedCopy(), "failed confirm is consumed")
        clipboard.accepts = true
        let retained = RestoreDiagnosticsCopyActions(write: clipboard.write)
        let sameTextA = privateResult("SentinelPrivateLayout")
        let differentLayout = RestoreResult(layoutID: UUID(), layoutName: sameTextA.layoutName,
            windowsResults: [WindowRestoreResult(appName: "SentinelPrivateApp",
                windowTitle: "SentinelPrivateWindow", status: .windowSkipped)])
        precondition(sameTextA.windowsResults[0].id != differentLayout.windowsResults[0].id)
        precondition(RestoreResultMapping.redactedDiagnostics(for: sameTextA, includeWindowDetails: true) ==
            RestoreResultMapping.redactedDiagnostics(for: differentLayout, includeWindowDetails: true))
        let oldView = copyView(sameTextA, revision: 41, actions: retained)
        oldView.requestDetailedCopy()
        let nextView = copyView(differentLayout, revision: 42, actions: retained)
        precondition(!nextView.confirmDetailedCopy() && clipboard.writes.count == 2,
            "same text but different layout and revision cannot inherit consent")
        nextView.requestDetailedCopy()
        precondition(nextView.confirmDetailedCopy() && clipboard.writes.count == 3,
            "fresh consent on new revision works")
        let sameLayoutNext = copyView(differentLayout, revision: 43, actions: retained)
        nextView.requestDetailedCopy()
        precondition(!sameLayoutNext.confirmDetailedCopy() && clipboard.writes.count == 3,
            "same layout and text on new revision cannot inherit consent")
        sameLayoutNext.requestDetailedCopy()
        precondition(sameLayoutNext.confirmDetailedCopy() && clipboard.writes.count == 4)
        print("RestoreDiagnosticsRemountTests: 28 checks passed")
    }
}
