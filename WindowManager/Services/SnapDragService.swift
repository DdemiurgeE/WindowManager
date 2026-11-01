import AppKit
import ApplicationServices
import Combine

/// Opt-in edge snapping. A global mouse monitor only observes events; it does
/// not intercept or synthesize input. AX writes happen once, after a real
/// focused standard window moved during the drag and the user releases at an
/// edge. No app windows or user defaults are changed by setup itself.
final class SnapDragService: ObservableObject {
    static let shared = SnapDragService()
    @Published private(set) var isMonitoring = false

    private var monitor: Any?
    private weak var windowService: WindowService?
    private var trackedWindow: AXUIElement?
    private var trackedPID: pid_t?
    private var gesture = SnapDragGesture()

    private init() {}

    func setup(windowService: WindowService) {
        self.windowService = windowService
        setEnabled(UserDefaults.standard.bool(forKey: "snapOnDragEnabled"))
    }

    func setEnabled(_ enabled: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        reset()
        guard enabled, PermissionsService.shared.checkAccessibilityPermission() else {
            isMonitoring = false
            return
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            DispatchQueue.main.async { self?.handle(event) }
        }
        isMonitoring = monitor != nil
    }

    private func handle(_ event: NSEvent) {
        guard let windowService else { reset(); return }
        switch event.type {
        case .leftMouseDragged:
            guard let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let focused = focusedStandardWindow(for: app.processIdentifier),
                  let position = axPosition(of: focused) else { reset(); return }
            if trackedPID != app.processIdentifier || trackedWindow == nil || !CFEqual(trackedWindow, focused) {
                // The first sample proves neither a user move nor an edge hit.
                // Only a cursor in the title bar can initiate this gesture.
                guard isPointInTitleBar(NSEvent.mouseLocation, window: focused, position: position) else {
                    reset(); return
                }
                trackedWindow = focused
                trackedPID = app.processIdentifier
                gesture.begin(at: position)
            } else {
                gesture.observe(position: position)
            }
        case .leftMouseUp:
            defer { reset() }
            guard gesture.isDraggingWindow, let trackedWindow, let trackedPID,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == trackedPID,
                  let focused = focusedStandardWindow(for: trackedPID), CFEqual(focused, trackedWindow) else { return }
            let pointer = NSEvent.mouseLocation
            let screens = NSScreen.screens
            let matches = screens.enumerated().filter { $0.element.frame.contains(pointer) }
            guard matches.count == 1, let match = matches.first,
                  let zone = SnapGeometry.edgeZone(at: pointer, screen: match.element.frame) else { return }
            let ids = DisplayIdentity.screenIDs(for: screens)
            _ = windowService.snapAXWindow(SystemAXWindowClient.Handle(focused), to: zone, displayID: ids[match.offset])
        default: break
        }
    }

    private func focusedStandardWindow(for pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = value as! AXUIElement
        var role: CFTypeRef?, subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) == .success,
              (role as? String) == (kAXWindowRole as String),
              AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole) == .success,
              (subrole as? String) == (kAXStandardWindowSubrole as String) else { return nil }
        return window
    }

    private func axPosition(of window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &position) else { return nil }
        return position
    }

    private func isPointInTitleBar(_ point: CGPoint, window: AXUIElement, position: CGPoint) -> Bool {
        guard let primary = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }) else { return false }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return false }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return false }
        let frame = WindowCoordinateConverter(primaryScreenFrame: primary.frame)
            .axOriginToScreenFrame(axOrigin: position, size: size)
        return SnapDragGesture.isTitleBarGrab(point, in: frame)
    }

    private func reset() {
        trackedWindow = nil
        trackedPID = nil
        gesture.reset()
    }
}
