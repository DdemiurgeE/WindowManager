import Foundation
import AppKit
import ApplicationServices

// Compile-time stand-in; no application is created or launched.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func openOrCreateMainWindow() {}
}

/// Only fake handles are returned to the actual production restore service.
private final class IntegrationAX: AXWindowClient {
    let handle = NSObject()
    var successfulHandle: NSObject?
    var state = false
    var nativeReadFailure: NativeFullscreenFailure?
    var positionReadFailure: AXError?
    var sizeReadFailure: AXError?
    var positionValue = CGPoint(x: 100, y: 100)
    var sizeValue = CGSize(width: 600, height: 400)
    var events: [String] = []
    var writtenHandles: [ObjectIdentifier] = []
    var nativeReads = 0
    var onSetPosition: (() -> Void)?
    var onSizeRead: (() -> Void)?

    func windows(for processIdentifier: pid_t) -> AXOperationResult<[AnyObject]> {
        .success([handle] + (successfulHandle.map { [$0] } ?? []))
    }
    func title(of window: AnyObject) -> AXOperationResult<String> {
        .success(window === successfulHandle ? "Synthetic successful window" : "Synthetic test window")
    }
    func role(of window: AnyObject) -> AXOperationResult<String> { .success("AXWindow") }
    func subrole(of window: AnyObject) -> AXOperationResult<String> { .success("AXStandardWindow") }
    func position(of window: AnyObject) -> AXOperationResult<CGPoint> {
        if let positionReadFailure { return .failure(positionReadFailure) }
        return .success(positionValue)
    }
    func size(of window: AnyObject) -> AXOperationResult<CGSize> {
        if let sizeReadFailure { return .failure(sizeReadFailure) }
        let value = sizeValue
        onSizeRead?()
        return .success(value)
    }
    func setPosition(_ value: CGPoint, of window: AnyObject) -> AXError {
        events.append("position")
        writtenHandles.append(ObjectIdentifier(window))
        positionValue = value
        onSetPosition?()
        return .success
    }
    func setSize(_ value: CGSize, of window: AnyObject) -> AXError {
        events.append("size")
        writtenHandles.append(ObjectIdentifier(window))
        sizeValue = value
        return .success
    }
    func fullscreen(of window: AnyObject) -> Result<Bool, NativeFullscreenFailure> {
        events.append("read-fullscreen")
        nativeReads += 1
        if window === successfulHandle { return .success(false) }
        return nativeReadFailure.map { .failure($0) } ?? .success(state)
    }
    func fullscreenSettable(of window: AnyObject) -> Result<Bool, NativeFullscreenFailure> { .success(true) }
    func setFullscreen(_ value: Bool, of window: AnyObject) -> Result<Void, NativeFullscreenFailure> {
        events.append(value ? "enter" : "exit")
        writtenHandles.append(ObjectIdentifier(window))
        state = value
        return .success(())
    }
}

@main struct WindowServiceIntegrationTests {
    static var failures = 0
    static var checks = 0

    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { failures += 1 }
        print("\(condition ? "PASS" : "FAIL"): \(message)")
    }

    static func wait(_ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(12)
        while !done() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(done(), "Synthetic restore completion timed out")
    }

    static func restore(_ service: WindowService, _ layout: Layout) -> RestoreResult {
        var result: RestoreResult?
        service.restoreLayout(layout, completion: { result = $0 })
        wait { result != nil }
        return result!
    }

    static func main() throws {
        // Read-only AppKit snapshots anchor production app/display resolution.
        // No real AX enumeration, setters, app launch, or system permission API.
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.activationPolicy == .regular && !$0.isTerminated
        }), let screen = NSScreen.screens.first else {
            fatalError("Read-only app/display snapshots unavailable; never launch an app to satisfy this test")
        }
        let ids = DisplayIdentity.screenIDs(for: NSScreen.screens)
        let frame = CGRect(x: screen.frame.minX + 100, y: screen.frame.minY + 100,
                           width: min(600, screen.frame.width / 2), height: min(400, screen.frame.height / 2))
        func window(_ state: Bool?, title: String = "Synthetic test window") -> WindowInfo {
            WindowInfo(appName: app.localizedName ?? "Unknown", windowTitle: title,
                       frame: frame, screenIndex: 0, screenID: ids[0], bundleIdentifier: app.bundleIdentifier,
                       savedDisplayFrame: screen.frame, savedVisibleFrame: screen.visibleFrame,
                       preservePresentation: false, savedScale: screen.backingScaleFactor, nativeFullscreen: state)
        }
        func layout(_ state: Bool?) -> Layout { Layout(name: "Synthetic integration", windows: [window(state)]) }

        for value in [true, false] {
            let fake = IntegrationAX(); fake.state = value
            check(WindowService(axClient: fake).capturedFullscreen(of: fake.handle) == value,
                  "Production capture helper preserves native \(value)")
        }
        for error: NativeFullscreenFailure in [.unsupported, .read] {
            let fake = IntegrationAX(); fake.nativeReadFailure = error
            check(WindowService(axClient: fake).capturedFullscreen(of: fake.handle) == nil,
                  "Production capture keeps unavailable native state unknown")
        }
        do {
            let fake = IntegrationAX(); fake.state = true; fake.nativeReadFailure = .unsupported
            let result = restore(WindowService(axClient: fake), layout(nil))
            check(result.windowsRestored == 1 && fake.events == ["position", "size"],
                  "Production legacy restore performs geometry only")
        }
        do {
            let fake = IntegrationAX(); fake.state = true
            let result = restore(WindowService(axClient: fake), layout(false))
            check(result.windowsRestored == 1 && fake.events.firstIndex(of: "exit")! < fake.events.firstIndex(of: "position")!,
                  "Production native-false restore exits before geometry")
        }
        do {
            let fake = IntegrationAX()
            let result = restore(WindowService(axClient: fake), layout(true))
            check(result.windowsRestored == 1 && fake.events.firstIndex(of: "position")! < fake.events.firstIndex(of: "enter")!,
                  "Production native-true restore sets geometry before entering")
        }
        do {
            let fake = IntegrationAX(); fake.nativeReadFailure = .read
            let service = WindowService(axClient: fake); let saved = layout(true)
            let result = restore(service, saved)
            check(result.windowsResults.first?.status == .fullscreenReadFailure && !fake.events.contains("position"),
                  "Production native read failure does not mutate geometry")
            fake.nativeReadFailure = nil
            check(service.retryMissingOrFailed(saved), "Manual retry accepts native failure")
            wait { !service.isRestoring }
            check(service.lastRestoreResult?.windowsRestored == 1 && fake.state,
                  "Production manual retry reaches verified native success")
        }

        // The synchronous setter/read-back is exact. The app later changes its
        // frame on the same display before the production async polls settle.
        for (initiallyFullscreen, dx, dw, expected) in [
            (false, 70.0, 30.0, WindowRestoreResult.WindowRestoreStatus.appImposedClamp),
            (false, 70.0, 0.0, .appImposedClamp), (false, 0.0, 30.0, .appImposedClamp),
            (false, 1.0, 1.0, .positionSet), (false, 0.0, 0.0, .positionSet),
            (true, 70.0, 30.0, .appImposedClamp)
        ] {
            let fake = IntegrationAX(); fake.state = initiallyFullscreen
            let service = WindowService(axClient: fake)
            fake.onSetPosition = {
                fake.onSetPosition = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                    fake.positionValue.x += dx
                    fake.sizeValue.width += dw
                }
            }
            var result: RestoreResult?
            service.restoreLayout(layout(false), completion: { result = $0 })
            wait { result != nil }
            check(result?.windowsResults.first?.status == expected,
                  "Final settled comparison uses target tolerance for dx=\(dx), dw=\(dw), initial fullscreen=\(initiallyFullscreen)")
            check(result?.windowsRestored == (expected == .positionSet ? 1 : 0),
                  "Final frame drift never inflates verified-restored count")
            check(fake.events.filter { $0 == "position" || $0 == "size" } == ["position", "size"],
                  "Final verification is read-only, not a corrective rewrite")
        }
        for failPosition in [true, false] {
            let fake = IntegrationAX()
            // The fourth native read is the last stable poll (initial read plus
            // three polls). Its size read succeeds; only the subsequent FINAL
            // frame comparison fails. Earlier settling failures have a distinct
            // fullscreenReadFailure status and would not satisfy this assertion.
            fake.onSizeRead = {
                if fake.nativeReads == 4 {
                    if failPosition { fake.positionReadFailure = .cannotComplete }
                    else { fake.sizeReadFailure = .cannotComplete }
                }
            }
            let result = restore(WindowService(axClient: fake), layout(false))
            check(result.windowsResults.first?.status == .axFailure && result.windowsRestored == 0,
                  "Final \(failPosition ? "position" : "size") read failure replaces earlier geometry success")
        }
        do {
            let fake = IntegrationAX(); let service = WindowService(axClient: fake)
            fake.onSetPosition = { service.cancelRestore() }
            service.restoreLayout(layout(true))
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            check(fake.events.filter { ["position", "size", "enter"].contains($0) } == ["position"] && !service.isRestoring,
                  "Production generation cancellation suppresses later writes")
        }
        do {
            let fake = IntegrationAX(); fake.successfulHandle = NSObject(); fake.nativeReadFailure = .read
            let service = WindowService(axClient: fake)
            let failed = window(true)
            let successful = window(false, title: "Synthetic successful window")
            let saved = Layout(name: "Synthetic partial retry", windows: [failed, successful])
            let initial = restore(service, saved)
            check(initial.windowsTotal == 2 && initial.windowsRestored == 1,
                  "Real initial restore seeds one success and one native failure")
            let previousSuccess = initial.windowsResults.first { $0.id == successful.id }
            let before = fake.events
            let revision = service.restoreResultRevision
            PermissionsService.shared.hasAccessibilityPermission = false
            check(service.retryMissingOrFailed(saved), "Permission-revoked partial retry is attempted")
            let denied = service.lastRestoreResult!
            check(denied.windowsResults.map(\.id) == initial.windowsResults.map(\.id) && denied.windowsTotal == 2,
                  "Permission denial preserves full result identity and ordering")
            check(denied.windowsResults.first { $0.id == successful.id }?.status == previousSuccess?.status && denied.windowsRestored == 1,
                  "Permission denial preserves the unaffected successful row and count")
            check(denied.windowsResults.first { $0.id == failed.id }?.status == .axFailure,
                  "Only the retried row becomes an AX failure")
            check(fake.events == before && !service.isRestoring && service.restoreResultRevision == revision + 1,
                  "Denied retry performs no fake AX work and records exactly one merged result")
            let copy = RestoreResultMapping.redactedDiagnostics(for: denied, includeWindowDetails: false)
            check(copy.contains("Restored: 1/2") && copy.contains("Accessibility failures: 1"),
                  "Copied diagnostics retain full-layout totals after denied retry")
            PermissionsService.shared.hasAccessibilityPermission = true
            fake.nativeReadFailure = nil
            let writesBefore = fake.writtenHandles.count
            check(service.retryMissingOrFailed(saved), "Retry remains available after permission recovery")
            wait { !service.isRestoring }
            check(service.lastRestoreResult?.windowsRestored == 2 && service.lastRestoreResult?.windowsTotal == 2,
                  "Recovered retry merges successful status into the full result")
            check(fake.writtenHandles.dropFirst(writesBefore).allSatisfy { $0 == ObjectIdentifier(fake.handle) },
                  "Recovered retry writes only the formerly failed fake window")
        }
        do {
            var json = try JSONSerialization.jsonObject(with: LayoutImportCodec.export([layout(true)])) as! [String: Any]
            var layouts = json["layouts"] as! [[String: Any]]
            var windows = layouts[0]["windows"] as! [[String: Any]]
            for bad: Any in [0, 1, "false", [false], ["a": true]] {
                windows[0]["nativeFullscreen"] = bad
                layouts[0]["windows"] = windows; json["layouts"] = layouts
                do {
                    _ = try LayoutImportCodec.decode(JSONSerialization.data(withJSONObject: json))
                    check(false, "Malformed native fullscreen must be rejected")
                } catch { check(true, "Malformed native fullscreen rejected") }
            }
            windows[0]["nativeFullscreen"] = NSNull()
            layouts[0]["windows"] = windows; json["layouts"] = layouts
            check(try LayoutImportCodec.decode(JSONSerialization.data(withJSONObject: json))[0].windows[0].nativeFullscreen == nil,
                  "Explicit JSON null remains unknown")
        }
        print("WindowServiceIntegrationTests: \(checks) checks, \(failures) failures; production restore/retry, fake AX/permissions, no live writes")
        exit(failures == 0 ? 0 : 1)
    }
}
