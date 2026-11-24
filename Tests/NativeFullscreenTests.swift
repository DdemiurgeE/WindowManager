import Foundation
import AppKit
import ApplicationServices

// Compile-time stand-in only; no application is created or launched.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func openOrCreateMainWindow() {}
}

private final class FakeAX: AXWindowClient {
    var state = false
    var readError: NativeFullscreenFailure?
    var writeError: NativeFullscreenFailure?
    var capabilityError: NativeFullscreenFailure?
    var settable = true
    var onDisplay = true
    var displayReadFails = false
    var acceptsTransition = true
    var settled = true
    var pending: (Bool, Int)?
    var queue: [() -> Void] = []
    var events: [String] = []
    var active = true
    var frameStatus: WindowRestoreResult.WindowRestoreStatus = .positionSet
    var status: WindowRestoreResult.WindowRestoreStatus?
    var completions = 0
    let handle = NSObject()
    func windows(for processIdentifier: pid_t) -> AXOperationResult<[AnyObject]> { .success([handle]) }
    func title(of window: AnyObject) -> AXOperationResult<String> { .success("") }
    func role(of window: AnyObject) -> AXOperationResult<String> { .success("AXWindow") }
    func subrole(of window: AnyObject) -> AXOperationResult<String> { .success("AXStandardWindow") }
    func position(of window: AnyObject) -> AXOperationResult<CGPoint> { .success(.zero) }
    func size(of window: AnyObject) -> AXOperationResult<CGSize> { .success(CGSize(width: 800, height: 600)) }
    func setPosition(_ position: CGPoint, of window: AnyObject) -> AXError { .success }
    func setSize(_ size: CGSize, of window: AnyObject) -> AXError { .success }
    func fullscreen(of window: AnyObject) -> Result<Bool, NativeFullscreenFailure> {
        events.append("read")
        return readError.map { .failure($0) } ?? .success(state)
    }
    func fullscreenSettable(of window: AnyObject) -> Result<Bool, NativeFullscreenFailure> {
        events.append("capability")
        return capabilityError.map { .failure($0) } ?? .success(settable)
    }
    func setFullscreen(_ value: Bool, of window: AnyObject) -> Result<Void, NativeFullscreenFailure> {
        events.append(value ? "enter" : "exit")
        if let writeError { return .failure(writeError) }
        if acceptsTransition { pending = (value, 2) }
        return .success(())
    }
    func start(_ desired: Bool?) {
        NativeFullscreenRestoreEngine(pollLimit: 5).restore(desired: desired,
            read: { self.fullscreen(of: self.handle) },
            capability: { self.fullscreenSettable(of: self.handle) },
            write: { self.setFullscreen($0, of: self.handle) },
            onTargetDisplay: { self.displayReadFails ? .failure(.read) : .success(self.onDisplay) },
            settled: { .success(self.settled) },
            restoreFrame: {
                precondition(!self.state || desired == nil, "Geometry must follow verified fullscreen exit")
                self.events.append("geometry"); self.onDisplay = true
                return self.frameStatus
            }, schedule: { self.queue.append($0) },
            shouldContinue: { self.active }, completion: { self.status = $0; self.completions += 1 })
    }
    func tick() {
        if let (value, remaining) = pending {
            if remaining == 1 { state = value; pending = nil }
            else { pending = (value, remaining - 1) }
        }
        if !queue.isEmpty { queue.removeFirst()() }
    }
    func drain() {
        var ticks = 0
        while !queue.isEmpty { tick(); ticks += 1; precondition(ticks < 100) }
        precondition(completions == 1)
    }
}

@main struct NativeFullscreenTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); checks += 1
    }
    static func main() throws {
        let fake = FakeAX()
        let service = WindowService(axClient: fake)
        for state in [true, false] {
            fake.state = state
            check(service.capturedFullscreen(of: fake.handle) == state, "Capture true/false uses AX, not geometry")
            let window = WindowInfo(appName: "Fake", windowTitle: "", frame: CGRect(x: 0, y: 0, width: 800, height: 600), screenIndex: 0, preservePresentation: !state, nativeFullscreen: state)
            let layout = Layout(name: "Fixture", windows: [window])
            let restored = try LayoutImportCodec.decode(LayoutImportCodec.export([layout]))
            check(restored[0].windows[0].nativeFullscreen == state, "Portable import/export retains independent native state")
            var json = try JSONSerialization.jsonObject(with: LayoutImportCodec.export([layout])) as! [String: Any]
            var layouts = json["layouts"] as! [[String: Any]]
            var windows = layouts[0]["windows"] as! [[String: Any]]
            windows[0].removeValue(forKey: "nativeFullscreen")
            layouts[0]["windows"] = windows; json["layouts"] = layouts
            let legacy = try LayoutImportCodec.decode(JSONSerialization.data(withJSONObject: json))
            check(legacy[0].windows[0].nativeFullscreen == nil, "Legacy is unknown, never false")
            for invalid in [1, "true", [true]] as [Any] {
                windows[0]["nativeFullscreen"] = invalid
                layouts[0]["windows"] = windows; json["layouts"] = layouts
                do { _ = try LayoutImportCodec.decode(JSONSerialization.data(withJSONObject: json)); preconditionFailure("Invalid native state accepted") }
                catch { checks += 1 }
            }
        }
        for error: NativeFullscreenFailure in [.unsupported, .read] {
            fake.readError = error
            check(service.capturedFullscreen(of: fake.handle) == nil, "Unavailable capture remains unknown")
        }
        let enter = FakeAX(); enter.start(true)
        check(enter.status == nil && !enter.queue.isEmpty, "Entry returns without blocking on animation")
        enter.drain()
        check(enter.status == .positionSet && enter.events.filter { $0 == "enter" }.count == 1, "Entry verified")
        let move = FakeAX(); move.state = true; move.onDisplay = false; move.start(true); move.drain()
        check(move.events.filter { ["exit", "geometry", "enter"].contains($0) } == ["exit", "geometry", "enter"], "Wrong physical monitor exits, moves, then enters")
        let correct = FakeAX(); correct.state = true; correct.start(true); correct.drain()
        check(!correct.events.contains("exit") && !correct.events.contains("enter") && !correct.events.contains("geometry"), "Already fullscreen on target must not toggle")
        let animation = FakeAX(); animation.state = true; animation.settled = false; animation.start(false)
        animation.tick(); animation.tick(); animation.tick()
        check(!animation.events.contains("geometry"), "AX false alone does not mean the animation has settled")
        animation.settled = true; animation.drain()
        check(animation.status == .positionSet, "Stable geometry allows exit to continue")
        let exit = FakeAX(); exit.state = true; exit.start(false); exit.drain()
        check(exit.status == .positionSet && exit.events.filter { ["exit", "geometry", "enter"].contains($0) } == ["exit", "geometry"], "Saved false exits before geometry")
        let windowed = FakeAX(); windowed.start(false); windowed.drain()
        check(windowed.status == .positionSet && !windowed.events.contains("capability"), "No transition needs no write capability")
        let legacy = FakeAX(); legacy.readError = .unsupported; legacy.start(nil); legacy.drain()
        check(legacy.events == ["geometry"], "Legacy restore is geometry only")
        let unsupported = FakeAX(); unsupported.settable = false; unsupported.start(true); unsupported.drain()
        check(unsupported.status == .fullscreenUnsupported && !unsupported.events.contains("enter"), "Unsupported capability fails explicitly")
        let capability = FakeAX(); capability.capabilityError = .read; capability.start(true); capability.drain()
        check(capability.status == .fullscreenReadFailure, "Capability query failure explicit")
        let read = FakeAX(); read.readError = .read; read.start(true); read.drain()
        check(read.status == .fullscreenReadFailure && !read.events.contains("geometry"), "Read failure must not act like false")
        let write = FakeAX(); write.writeError = .write; write.start(true); write.drain()
        check(write.status == .fullscreenWriteFailure, "Write failure overrides geometry success")
        let timeout = FakeAX(); timeout.acceptsTransition = false; timeout.start(true); timeout.drain()
        check(timeout.status == .fullscreenTimeout, "Bounded timeout without accepted transition")
        let exitTimeout = FakeAX(); exitTimeout.state = true; exitTimeout.acceptsTransition = false; exitTimeout.start(false); exitTimeout.drain()
        check(exitTimeout.status == .fullscreenTimeout && !exitTimeout.events.contains("geometry"), "Exit timeout prohibits geometry")
        let lateRead = FakeAX(); lateRead.start(true); lateRead.readError = .read; lateRead.drain()
        check(lateRead.status == .fullscreenReadFailure, "Transition read failure explicit")
        let mismatch = FakeAX(); mismatch.start(true); mismatch.onDisplay = false; mismatch.drain()
        check(mismatch.status == .fullscreenDisplayMismatch, "Final fullscreen monitor verified")
        let displayRead = FakeAX(); displayRead.displayReadFails = true; displayRead.start(true); displayRead.drain()
        check(displayRead.status == .fullscreenReadFailure, "Display readback failure explicit")
        let cancel = FakeAX(); cancel.state = true; cancel.onDisplay = false; cancel.start(true)
        cancel.active = false; let eventCount = cancel.events.count; cancel.drain()
        check(cancel.status == .restoreSuperseded && cancel.events.count == eventCount, "Cancelled continuation must not read, move or reenter")
        let before = FakeAX(); before.active = false; before.start(true); before.drain()
        check(before.events.isEmpty && before.status == .restoreSuperseded, "Cancelled before start has no effects")
        let geometryFailure = FakeAX(); geometryFailure.frameStatus = .axFailure; geometryFailure.start(true); geometryFailure.drain()
        check(geometryFailure.status == .axFailure && !geometryFailure.events.contains("enter"), "Geometry failure prevents enter")
        // The fullscreen intent follows the existing physical resolver even when
        // display order/geometry changes, never the old numeric monitor index.
        let primary = DisplaySnapshot(screenID: "display_primary", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 850), scale: 2, index: 0)
        let external = DisplaySnapshot(screenID: "display_external", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), visibleFrame: CGRect(x: -1920, y: 25, width: 1920, height: 1030), scale: 1, index: 1)
        let topology = ScreenConfiguration(screens: [.init(id: "display_primary", frame: primary.frame, visibleFrame: primary.visibleFrame, scale: 2)])
        let dockHidden = ScreenConfiguration(screens: [.init(id: "display_primary", frame: primary.frame, visibleFrame: primary.frame, scale: 2)])
        let rearranged = ScreenConfiguration(screens: [.init(id: "display_primary", frame: external.frame, visibleFrame: external.frame, scale: 2)])
        check(topology.hasSamePhysicalTopology(as: dockHidden), "Fullscreen/Dock visible-frame changes must not cancel or restart restore")
        check(!topology.hasSamePhysicalTopology(as: rearranged), "Physical arrangement change invalidates restore")
        let saved = WindowInfo(appName: "Fake", windowTitle: "", frame: primary.frame, screenIndex: 0,
            relativeFrame: CGRect(x: 0, y: 0, width: 1, height: 1), screenID: "display_external", preservePresentation: true, nativeFullscreen: true)
        let fullscreenLayout = Layout(name: "Fixture", windows: [saved])
        let candidate = WindowAssignmentSnapshot(id: "fake", bundleID: nil, appName: "Fake", title: "", role: nil, subrole: nil, frame: primary.frame)
        let plan = RestorePlanner().plan(layout: fullscreenLayout, current: [candidate], displays: [primary, external])
        check(plan.items[0].chosenDisplay?.screenID == "display_external" && plan.items[0].targetFrame == external.frame, "Fullscreen follows saved physical display after reordering")
        check(RestorePreviewPresentation(plan: plan).rows[0].result.contains("native fullscreen → on"), "Preview discloses native fullscreen intent")
        let missing = RestorePlanner().plan(layout: fullscreenLayout, current: [candidate], displays: [primary])
        check(missing.items[0].isSkipped, "Missing physical display does not move fullscreen to another monitor")
        let duplicates = RestorePlanner().plan(layout: fullscreenLayout, current: [candidate], displays: [external, external])
        check(duplicates.items[0].isSkipped, "Ambiguous physical display skips fullscreen")
        let failures: [WindowRestoreResult.WindowRestoreStatus] = [.fullscreenUnsupported, .fullscreenReadFailure, .fullscreenWriteFailure, .fullscreenTimeout, .fullscreenDisplayMismatch]
        let results = failures.map { WindowRestoreResult(appName: "Private", windowTitle: "Sensitive", status: $0) }
        let result = RestoreResult(layoutName: "Private", windowsResults: results)
        check(result.windowsRestored == 0 && result.fullscreenFailureCount == 5, "Fullscreen failures never count as restored")
        check(RestoreResultMapping.retryableIDs(in: results).count == 5, "All fullscreen failures manually retryable")
        let retryWindows = results.map { WindowInfo(id: $0.id, appName: "Fake", windowTitle: "", frame: .zero, screenIndex: 0) }
        check(RestoreResultMapping.retryableMissingIDs(in: retryWindows.reversed(), results: results).count == 5, "Auto retry includes fullscreen failures by saved identity")
        check(result.compactDiagnosticsDescription.contains("Fullscreen failures: 5"), "Summary includes fullscreen failures")
        let redacted = RestoreResultMapping.redactedDiagnostics(for: result, includeWindowDetails: false)
        check(redacted.contains("unsupported 1") && redacted.contains("read 1") && redacted.contains("write 1") && redacted.contains("timeout 1") && redacted.contains("wrong display 1"), "Redacted summary names each fullscreen failure category")
        check(redacted.contains("Fullscreen failures: 5") && !redacted.contains("Sensitive") && !redacted.contains("Private"), "Redacted copy counts failures without names")
        check(RestoreResultMapping.redactedDiagnostics(for: result, includeWindowDetails: true).contains("fullscreenTimeout"), "Detailed diagnostics name exact outcome")
        print("NativeFullscreenTests: \(checks) checks passed (fake AX only; no live writes)")
    }
}
