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
            print("Skipping window '\(title)' - outside screen bounds (ax: \(axPosition), screen: \(screenFrame))")
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

        print("Captured '\(title)' on screen \(screenIndex) [relative=\(relativeFrame)]")
        return WindowInfo(
            appName: appName,
            windowTitle: title,
            frame: screenFrame,
            screenIndex: screenIndex,
            relativeFrame: relativeFrame,
            screenID: getScreenID(for: targetScreen),
            bundleIdentifier: bundleIdentifier,
            axRole: roleRef as? String,
            axSubrole: subroleRef as? String
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
    func restoreLayout(_ layout: Layout) -> RestoreResult {
        var results: [WindowRestoreResult] = []

        guard PermissionsService.shared.checkAccessibilityPermission() else {
            print("No accessibility permission")
            return RestoreResult(layoutName: layout.name, windowsResults: results)
        }
        
        let screens = NSScreen.screens
        guard coordinateConverter != nil else {
            let unavailable = layout.windows.map { WindowRestoreResult(appName: $0.appName, windowTitle: $0.windowTitle, status: .coordinateUnavailable) }
            return RestoreResult(layoutName: layout.name, windowsResults: unavailable)
        }
        let runningApps = NSWorkspace.shared.runningApplications
        
        print("=== Restoring layout: \(layout.name) ===")
        for (index, screen) in screens.enumerated() {
            print("Screen \(index): frame=\(screen.frame)")
        }
        
        var assignmentStatuses: [UUID: WindowAssignmentStatus] = [:]
        var assignedElements: [UUID: AnyObject] = [:]
        var preparedApps = Set<pid_t>()

        for windowInfo in layout.windows {
            let targetFrame = resolveTargetFrame(for: windowInfo, screens: screens)

            let app = runningApps.first(where: { windowInfo.bundleIdentifier != nil && $0.bundleIdentifier == windowInfo.bundleIdentifier })
                ?? runningApps.first(where: { $0.localizedName == windowInfo.appName })
            guard let app else {
                print("  App not found: \(windowInfo.appName)")
                results.append(WindowRestoreResult(appName: windowInfo.appName, windowTitle: windowInfo.windowTitle, status: .appNotFound))
                continue
            }
            
            let pid = app.processIdentifier
            if !preparedApps.contains(pid) {
                preparedApps.insert(pid)
                let appTargets = layout.windows.filter {
                    ($0.bundleIdentifier != nil && $0.bundleIdentifier == app.bundleIdentifier) ||
                    ($0.bundleIdentifier == nil && $0.appName == app.localizedName)
                }
                if case .success(let windowArray) = axClient.windows(for: pid) {
                    let snapshots = windowArray.enumerated().compactMap { index, element -> WindowAssignmentSnapshot? in
                        guard case .success(let title) = axClient.title(of: element),
                              case .success(let position) = axClient.position(of: element),
                              case .success(let size) = axClient.size(of: element) else { return nil }
                        let frame = coordinateConverter?.axOriginToScreenFrame(axOrigin: position, size: size) ?? CGRect(origin: position, size: size)
                        return WindowAssignmentSnapshot(id: "\(pid):\(index)", bundleID: app.bundleIdentifier,
                                              appName: app.localizedName ?? "Unknown", title: title,
                                              role: axRole(element), subrole: axSubrole(element), frame: frame)
                    }
                    let assignments = WindowAssigner().assign(targets: appTargets.map {
                        WindowAssignmentSnapshot(id: $0.id.uuidString, bundleID: $0.bundleIdentifier, appName: $0.appName,
                                       title: $0.windowTitle == "Untitled" ? "" : $0.windowTitle,
                                       role: $0.axRole, subrole: $0.axSubrole, frame: $0.frame)
                    }, current: snapshots)
                    for assignment in assignments {
                        assignmentStatuses[UUID(uuidString: assignment.targetID)!] = assignment.status
                        if case .matched(let currentID) = assignment.status,
                           let index = Int(currentID.split(separator: ":").last ?? ""), index < windowArray.count {
                            assignedElements[UUID(uuidString: assignment.targetID)!] = windowArray[index]
                        }
                    }
                }
            }

            guard let assignment = assignmentStatuses[windowInfo.id],
                  case .matched = assignment,
                  let element = assignedElements[windowInfo.id],
                  case .success(let title) = axClient.title(of: element) else {
                results.append(WindowRestoreResult(appName: windowInfo.appName, windowTitle: windowInfo.windowTitle, status: .windowSkipped))
                continue
            }
            let status = setWindowFrame(element, frame: targetFrame, debugName: "\(windowInfo.appName) — \(title)")
            results.append(WindowRestoreResult(appName: windowInfo.appName, windowTitle: title, status: status))
        }

        print("[RestoreResult] \(RestoreResult(layoutName: layout.name, windowsResults: results).summaryDescription)")
        return RestoreResult(layoutName: layout.name, windowsResults: results)
    }

    /// Вычисляет абсолютный targetFrame для окна при восстановлении.
    ///
    /// Display selection is deliberately completed before relative-frame conversion.
    /// NSScreenNumber/CGDirectDisplayID is only a current-observation key: macOS may
    /// assign a different number after hot-plug. It is therefore never treated as a
    /// permanent vendor/model/serial hardware identity.
    private func resolveTargetFrame(for windowInfo: WindowInfo, screens: [NSScreen]) -> CGRect {
        let displays = screens.enumerated().map { index, screen in
            DisplaySnapshot(screenID: getScreenID(for: screen), frame: screen.frame, index: index)
        }
        let snapshot = WindowSnapshot(
            frame: windowInfo.frame,
            relativeFrame: windowInfo.relativeFrame,
            screenID: windowInfo.screenID,
            screenIndex: windowInfo.screenIndex
        )
        guard let resolved = ScreenResolver().resolve(window: snapshot, displays: displays) else {
            print("[WindowRestore] Window '\(windowInfo.appName)' has no available display; using saved frame")
            return windowInfo.frame
        }
        print("[WindowRestore] Window '\(windowInfo.appName)' selected display index \(resolved.display.index) via \(resolved.selection)")
        return resolved.frame
    }
    
    private func setWindowFrame(_ windowElement: AnyObject, frame: CGRect, debugName: String = "") -> WindowRestoreResult.WindowRestoreStatus {
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
            onError: { print("[\(debugName)] \($0)") }
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
