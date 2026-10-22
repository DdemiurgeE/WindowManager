import Foundation
import AppKit
import ApplicationServices
import Combine

enum AXOperationResult<Value> {
    case success(Value)
    case failure(AXError)
}

protocol AXWindowClient {
    func windows(for processIdentifier: pid_t) -> AXOperationResult<[AnyObject]>
    func title(of window: AnyObject) -> AXOperationResult<String>
    func role(of window: AnyObject) -> AXOperationResult<String>
    func subrole(of window: AnyObject) -> AXOperationResult<String>
    func position(of window: AnyObject) -> AXOperationResult<CGPoint>
    func size(of window: AnyObject) -> AXOperationResult<CGSize>
    func setPosition(_ position: CGPoint, of window: AnyObject) -> AXError
    func setSize(_ size: CGSize, of window: AnyObject) -> AXError
}

struct SystemAXWindowClient: AXWindowClient {
    final class Handle {
        let element: AXUIElement
        init(_ element: AXUIElement) { self.element = element }
    }

    func windows(for processIdentifier: pid_t) -> AXOperationResult<[AnyObject]> {
        let app = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard error == .success, let elements = value as? [AXUIElement] else { return .failure(error) }
        return .success(elements.map { Handle($0) as AnyObject })
    }

    func title(of window: AnyObject) -> AXOperationResult<String> {
        guard let window = window as? Handle else { return .failure(.illegalArgument) }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(window.element, kAXTitleAttribute as CFString, &value)
        guard error == .success, let title = value as? String else { return .failure(error) }
        return .success(title)
    }

    func role(of window: AnyObject) -> AXOperationResult<String> { attribute(kAXRoleAttribute, of: window) }
    func subrole(of window: AnyObject) -> AXOperationResult<String> { attribute(kAXSubroleAttribute, of: window) }

    private func attribute(_ name: String, of window: AnyObject) -> AXOperationResult<String> {
        guard let window = window as? Handle else { return .failure(.illegalArgument) }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(window.element, name as CFString, &value)
        guard error == .success, let result = value as? String else { return .failure(error) }
        return .success(result)
    }

    func position(of window: AnyObject) -> AXOperationResult<CGPoint> {
        guard let window = window as? Handle else { return .failure(.illegalArgument) }
        return read(.cgPoint, kAXPositionAttribute, window.element)
    }
    func size(of window: AnyObject) -> AXOperationResult<CGSize> {
        guard let window = window as? Handle else { return .failure(.illegalArgument) }
        return read(.cgSize, kAXSizeAttribute, window.element)
    }

    private func read<T>(_ type: AXValueType, _ attribute: String, _ element: AXUIElement) -> AXOperationResult<T> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else { return .failure(error) }
        let axValue = value as! AXValue
        var result: T? = nil
        if type == .cgPoint { var point = CGPoint.zero; guard AXValueGetValue(axValue, type, &point) else { return .failure(.failure) }; result = point as? T }
        else { var size = CGSize.zero; guard AXValueGetValue(axValue, type, &size) else { return .failure(.failure) }; result = size as? T }
        return result.map(AXOperationResult.success) ?? .failure(.failure)
    }

    func setPosition(_ position: CGPoint, of window: AnyObject) -> AXError {
        guard let window = window as? Handle else { return .illegalArgument }
        var value = position
        guard let axValue = AXValueCreate(.cgPoint, &value) else { return .failure }
        return AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, axValue)
    }

    func setSize(_ size: CGSize, of window: AnyObject) -> AXError {
        guard let window = window as? Handle else { return .illegalArgument }
        var value = size
        guard let axValue = AXValueCreate(.cgSize, &value) else { return .failure }
        return AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, axValue)
    }
}

class WindowService: ObservableObject {
    @Published var currentWindows: [WindowInfo] = []
    @Published var isCapturing = false
    @Published private(set) var lastRestoreResult: RestoreResult?
    @Published private(set) var restoreResultRevision = 0
    @Published private(set) var diagnosticsPresentation = RestoreDiagnosticsPresentation()
    var restoreDiagnosticsExpanded: Bool {
        diagnosticsPresentation.isExpanded(for: restoreResultRevision)
    }
    private(set) var restoreHistory: [RestoreResult] = []
    private let maxRestoreHistoryEntries = 20
    private let axClient: AXWindowClient

    init(axClient: AXWindowClient = SystemAXWindowClient()) {
        self.axClient = axClient
    }

    private func axRole(_ window: AnyObject) -> String? {
        guard case .success(let value) = axClient.role(of: window) else { return nil }
        return value
    }

    private func axSubrole(_ window: AnyObject) -> String? {
        guard case .success(let value) = axClient.subrole(of: window) else { return nil }
        return value
    }
    
    func captureCurrentLayout() -> [WindowInfo] {
        var windows: [WindowInfo] = []
        
        guard PermissionsService.shared.checkAccessibilityPermission() else {
            print("No accessibility permission")
            return windows
        }
        
        let runningApps = NSWorkspace.shared.runningApplications
        let screens = NSScreen.screens
        
        for app in runningApps {
            guard app.activationPolicy == .regular,
                  app.processIdentifier > 0,
                  !app.isTerminated else { continue }
            
            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            
            let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            
            if result == .success, let windowArray = windowsRef as? [AXUIElement] {
                for windowElement in windowArray {
                    if let windowInfo = self.getWindowInfo(from: windowElement, appName: app.localizedName ?? "Unknown", bundleIdentifier: app.bundleIdentifier, screens: screens) {
                        windows.append(windowInfo)
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            self.currentWindows = windows
        }
        
        return windows
    }
    
    /// The primary display anchors the global AX/Quartz coordinate space.
    /// NSScreen.main is intentionally not used: it follows keyboard focus.
    private var coordinateConverter: WindowCoordinateConverter? {
        guard let primaryScreen = NSScreen.screens.first(where: {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return number.uint32Value == CGMainDisplayID()
        }) else { return nil }
        return WindowCoordinateConverter(primaryScreenFrame: primaryScreen.frame)
    }

    private func getWindowInfo(from windowElement: AXUIElement, appName: String, bundleIdentifier: String?, screens: [NSScreen]) -> WindowInfo? {
        var titleRef: CFTypeRef?
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var roleRef: CFTypeRef?
        var subroleRef: CFTypeRef?
        
        // Получаем заголовок окна
        AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
        AXUIElementCopyAttributeValue(windowElement, kAXRoleAttribute as CFString, &roleRef)
        AXUIElementCopyAttributeValue(windowElement, kAXSubroleAttribute as CFString, &subroleRef)
        let title = titleRef as? String ?? "Untitled"
        
        // Получаем позицию окна в пространстве AX/Quartz:
        //   origin = верхний-левый угол первичного экрана, Y растёт вниз.
        AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionRef)
        var axPosition = CGPoint.zero
        if let positionValue = positionRef {
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &axPosition)
        }
        
        // Получаем размер
        AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef)
        var size = CGSize.zero
        if let sizeValue = sizeRef {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }
        
        guard size.width >= 50 && size.height >= 50 else { return nil }

        // Конвертируем AX/Quartz → NSScreen (абсолютные координаты).
        guard let coordinateConverter else { return nil }
        let screenFrame = coordinateConverter.axOriginToScreenFrame(
            axOrigin: axPosition,
            size: CGSize(width: max(size.width, 100), height: max(size.height, 100))
        )

        // Отсеиваем окна полностью вне всех экранов
        let allScreensUnion = screens.reduce(CGRect.null) { $0.union($1.frame) }
        guard screenFrame.intersects(allScreensUnion) else {
            print("Skipping window - outside screen bounds (ax: \(axPosition), screen: \(screenFrame))")
            return nil
        }

        let screenIndex = self.getScreenIndex(for: screenFrame, screens: screens)

        // Вычисляем relativeFrame — позицию окна относительно его экрана.
        // Это позволяет корректно восстановить позицию даже если macOS
        // изменила абсолютное расположение мониторов (что происходит при каждом переподключении).
        let targetScreen = screens[screenIndex]
        let relativeFrame = CGRect(
            x: (screenFrame.origin.x - targetScreen.frame.origin.x) / targetScreen.frame.width,
            y: (screenFrame.origin.y - targetScreen.frame.origin.y) / targetScreen.frame.height,
            width: screenFrame.width / targetScreen.frame.width,
            height: screenFrame.height / targetScreen.frame.height
        )

        print("Captured window on screen \(screenIndex) [relative=\(relativeFrame)]")
        return WindowInfo(
            appName: appName,
            windowTitle: title,
            frame: screenFrame,
            screenIndex: screenIndex,
            relativeFrame: relativeFrame,
            screenID: getScreenID(for: targetScreen),
            bundleIdentifier: bundleIdentifier,
            axRole: roleRef as? String,
            axSubrole: subroleRef as? String,
            savedDisplayFrame: targetScreen.frame,
            savedVisibleFrame: targetScreen.visibleFrame,
            preservePresentation: screenFrame == targetScreen.frame || screenFrame == targetScreen.visibleFrame,
            savedScale: targetScreen.backingScaleFactor
        )
    }
    
    private func getScreenIndex(for frame: CGRect, screens: [NSScreen]) -> Int {
        // Находим экран с максимальной площадью пересечения с окном
        var bestIndex = 0
        var bestArea: CGFloat = 0

        for (index, screen) in screens.enumerated() {
            let intersection = screen.frame.intersection(frame)
            guard !intersection.isNull else { continue }
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        return bestIndex
    }
    
    @discardableResult
    func restoreLayout(_ layout: Layout, windowIDs: Set<UUID>? = nil) -> RestoreResult {
        let targets = windowIDs.map { ids in layout.windows.filter { ids.contains($0.id) } } ?? layout.windows

        guard PermissionsService.shared.checkAccessibilityPermission() else {
            print("No accessibility permission")
            return record(RestoreResult(layoutID: layout.id, layoutName: layout.name, windowsResults: []))
        }
        let (plan, elements) = makeRestorePlan(layout: layout, targets: targets)
        let results = plan.items.map { item -> WindowRestoreResult in
            guard let frame = item.targetFrame, let candidateID = item.candidateID,
                  let element = elements[candidateID] else {
                return RestorePlanResultMapping.result(forSkipped: item)
            }
            guard coordinateConverter != nil else {
                return WindowRestoreResult(id: item.windowID, appName: item.appName, windowTitle: item.windowTitle, status: .coordinateUnavailable)
            }
            let title = (try? axTitle(element)) ?? item.windowTitle
            return WindowRestoreResult(id: item.windowID, appName: item.appName, windowTitle: title,
                status: setWindowFrame(element, frame: frame))
        }
        let result = RestoreResult(layoutID: layout.id, layoutName: layout.name, windowsResults: results)
        if let previous = lastRestoreResult, previous.layoutID == layout.id, windowIDs != nil {
            return record(RestoreResultMapping.merged(previous: previous, retry: result))
        }
        return record(result)
    }

    @discardableResult
    func retryMissingOrFailed(_ layout: Layout) -> RestoreResult? {
        guard let previous = lastRestoreResult, previous.layoutID == layout.id else { return nil }
        let ids = RestoreResultMapping.retryableIDs(in: previous.windowsResults)
        guard !ids.isEmpty else { return nil }
        return restoreLayout(layout, windowIDs: ids)
    }

    @discardableResult
    func record(_ result: RestoreResult) -> RestoreResult {
        lastRestoreResult = result
        restoreResultRevision += 1
        restoreHistory.append(result)
        if restoreHistory.count > maxRestoreHistoryEntries {
            restoreHistory.removeFirst()
        }
        return result
    }

    func hideRestoreDiagnostics() {
        diagnosticsPresentation.hide(restoreResultRevision)
    }

    func showRestoreDiagnostics() {
        diagnosticsPresentation.show()
    }

    /// Computes the exact decisions used by `restoreLayout` without calling an AX setter.
    func planRestore(_ layout: Layout, windowIDs: Set<UUID>? = nil) -> WindowRestorePlan {
        let targets = windowIDs.map { ids in layout.windows.filter { ids.contains($0.id) } } ?? layout.windows
        return makeRestorePlan(layout: layout, targets: targets).plan
    }

    func dryRunRestore(_ layout: Layout, windowIDs: Set<UUID>? = nil) -> WindowRestorePlan {
        planRestore(layout, windowIDs: windowIDs)
    }

    private func axTitle(_ element: AnyObject) throws -> String {
        guard case .success(let title) = axClient.title(of: element) else { throw NSError(domain: "WindowManager", code: 1) }
        return title
    }

    private func makeRestorePlan(layout: Layout, targets: [WindowInfo]) -> (plan: WindowRestorePlan, elements: [String: AnyObject]) {
        let screens = NSScreen.screens
        let displays = screens.enumerated().map { index, screen in
            DisplaySnapshot(screenID: getScreenID(for: screen), frame: screen.frame,
                visibleFrame: screen.visibleFrame, scale: screen.backingScaleFactor, index: index)
        }
        let apps = NSWorkspace.shared.runningApplications
        var snapshots: [WindowAssignmentSnapshot] = []
        var elements: [String: AnyObject] = [:]
        var missingApps = Set<UUID>()
        var axFailures = Set<UUID>()
        var axFailureApps = Set<pid_t>()
        var processedPIDs = Set<pid_t>()
        for target in targets {
            let app: NSRunningApplication?
            if let bundleIdentifier = target.bundleIdentifier {
                app = apps.first(where: { $0.bundleIdentifier == bundleIdentifier })
            } else {
                app = apps.first(where: { $0.localizedName == target.appName })
            }
            guard let app else {
                missingApps.insert(target.id)
                continue
            }
            guard processedPIDs.insert(app.processIdentifier).inserted else { continue }
            guard case .success(let windows) = axClient.windows(for: app.processIdentifier) else {
                axFailureApps.insert(app.processIdentifier)
                continue
            }
            var targetReadFailed = false
            for (index, element) in windows.enumerated() {
                guard case .success(let title) = axClient.title(of: element),
                      case .success(let position) = axClient.position(of: element),
                      case .success(let size) = axClient.size(of: element) else { targetReadFailed = true; continue }
                let id = "\(app.processIdentifier):\(index)"
                let frame = coordinateConverter?.axOriginToScreenFrame(axOrigin: position, size: size) ?? CGRect(origin: position, size: size)
                snapshots.append(WindowAssignmentSnapshot(id: id, bundleID: app.bundleIdentifier,
                    appName: app.localizedName ?? "Unknown", title: title, role: axRole(element),
                    subrole: axSubrole(element), frame: frame))
                elements[id] = element
            }
            if targetReadFailed {
                axFailureApps.insert(app.processIdentifier)
            }
        }
        var plan = RestorePlanner().plan(layout: layout, targets: targets, current: snapshots, displays: displays)
        // An unreadable window must not poison every target belonging to its app.
        // Keep planner matches intact and only annotate unmatched targets for the
        // app whose AX data could not be read.
        if !axFailureApps.isEmpty {
            let appTargets = targets.filter { target in
                apps.contains { app in
                    axFailureApps.contains(app.processIdentifier) &&
                    (target.bundleIdentifier == app.bundleIdentifier || target.appName == app.localizedName)
                }
            }
            axFailures.formUnion(RestorePlanAXFailureScope.idsToMark(
                plan: plan, targetIDs: Set(appTargets.map(\.id))))
        }
        if !missingApps.isEmpty || !axFailures.isEmpty {
            plan = WindowRestorePlan(layoutName: plan.layoutName, items: plan.items.map { item in
                guard missingApps.contains(item.windowID) || axFailures.contains(item.windowID) else { return item }
                return WindowRestorePlanItem(windowID: item.windowID, appName: item.appName, windowTitle: item.windowTitle,
                    chosenDisplay: nil, targetFrame: nil, candidateID: nil, confidence: .none,
                    reason: axFailures.contains(item.windowID) ? "Accessibility data could not be read" : "application is not running",
                    skipReason: axFailures.contains(item.windowID) ? .axFailure : .appNotFound)
            })
        }
        return (plan, elements)
    }

    /// Вычисляет абсолютный targetFrame для окна при восстановлении.
    ///
    /// Display selection is deliberately completed before relative-frame conversion.
    /// NSScreenNumber/CGDirectDisplayID is only a current-observation key: macOS may
    /// assign a different number after hot-plug. It is therefore never treated as a
    /// permanent vendor/model/serial hardware identity.
    private func resolveTargetFrame(for windowInfo: WindowInfo, screens: [NSScreen]) -> CGRect {
        let displays = screens.enumerated().map { index, screen in
            DisplaySnapshot(screenID: getScreenID(for: screen), frame: screen.frame, visibleFrame: screen.visibleFrame, scale: screen.backingScaleFactor, index: index)
        }
        let snapshot = WindowSnapshot(
            frame: windowInfo.frame,
            relativeFrame: windowInfo.relativeFrame,
            screenID: windowInfo.screenID,
            screenIndex: windowInfo.screenIndex,
            savedDisplayFrame: windowInfo.savedDisplayFrame,
            savedVisibleFrame: windowInfo.savedVisibleFrame,
            preservePresentation: windowInfo.preservePresentation ?? false,
            savedScale: windowInfo.savedScale
        )
        guard let resolved = ScreenResolver().resolve(window: snapshot, displays: displays) else {
            print("[WindowRestore] No available display; using saved frame")
            return windowInfo.frame
        }
        print("[WindowRestore] Selected display index \(resolved.display.index) via \(resolved.selection)")
        return resolved.frame
    }
    
    private func setWindowFrame(_ windowElement: AnyObject, frame: CGRect) -> WindowRestoreResult.WindowRestoreStatus {
        guard let coordinateConverter else { return .coordinateUnavailable }
        let expectedPosition = coordinateConverter.screenFrameToAXOrigin(frame)
        let expectedSize = frame.size
        let engine = FrameRestoreEngine()
        let outcome = engine.restore(
            position: expectedPosition,
            size: expectedSize,
            setPosition: { position in
                let error = self.axClient.setPosition(position, of: windowElement)
                return error == .success ? .success(()) : .failure(.message("position set AXError \(error.rawValue)"))
            },
            setSize: { size in
                let error = self.axClient.setSize(size, of: windowElement)
                return error == .success ? .success(()) : .failure(.message("size set AXError \(error.rawValue)"))
            },
            read: {
                let positionResult = self.axClient.position(of: windowElement)
                guard case .success(let position) = positionResult else {
                    if case .failure(let error) = positionResult { return .failure(.message("position read AXError \(error.rawValue)")) }
                    return .failure(.message("position read failed"))
                }
                let sizeResult = self.axClient.size(of: windowElement)
                guard case .success(let size) = sizeResult else {
                    if case .failure(let error) = sizeResult { return .failure(.message("size read AXError \(error.rawValue)")) }
                    return .failure(.message("size read failed"))
                }
                return .success(WindowFrameReadback(position: position, size: size))
            },
            onError: { message in
                // Engine errors are strings; only known AX reason/code shapes may reach the console.
                let pattern = #"^(position|size) (set|read) AXError -?[0-9]+$"#
                let isKnownReason = message.range(of: pattern, options: .regularExpression) != nil ||
                    message == "position read failed" || message == "size read failed"
                let reason = isKnownReason ? message : "AX frame operation failed"
                print("[WindowRestore] \(reason)")
            }
        )
        switch outcome {
        case .exact: return .positionSet
        case .appImposedClamp: return .appImposedClamp
        case .axFailure: return .axFailure
        case .superseded: return .restoreSuperseded
        }
    }
    func getScreensInfo() -> String {
        let screens = NSScreen.screens
        var info = "Detected \(screens.count) screen(s):\n"
        
        for (index, screen) in screens.enumerated() {
            let frame = screen.frame
            info += "Screen \(index): \(Int(frame.width))x\(Int(frame.height)) at (\(Int(frame.origin.x)), \(Int(frame.origin.y)))\n"
        }
        
        return info
    }
    
    func getCurrentScreenConfiguration() -> ScreenConfiguration {
        let screens = NSScreen.screens
        let screenIDs = screens.map { getScreenID(for: $0) }
        return ScreenConfiguration(screenIDs: screenIDs)
    }
    
    private func getScreenID(for screen: NSScreen) -> String {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "screen_\(screenNumber.intValue)"
        }
        
        let frame = screen.frame
        return "screen_\(Int(frame.width))x\(Int(frame.height))_\(Int(frame.origin.x))_\(Int(frame.origin.y))"
    }
}

extension WindowService: RestorePreviewPlanning {
    func previewPlan(for layout: Layout) -> WindowRestorePlan {
        dryRunRestore(layout)
    }
}
