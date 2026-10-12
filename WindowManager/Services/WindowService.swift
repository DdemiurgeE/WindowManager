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
                    if let windowInfo = self.getWindowInfo(from: windowElement, appName: app.localizedName ?? "Unknown", screens: screens) {
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

    private func getWindowInfo(from windowElement: AXUIElement, appName: String, screens: [NSScreen]) -> WindowInfo? {
        var titleRef: CFTypeRef?
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        
        // Получаем заголовок окна
        AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
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
            screenID: getScreenID(for: targetScreen)
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
        
        for windowInfo in layout.windows {
            let targetFrame = resolveTargetFrame(for: windowInfo, screens: screens)

            guard let app = runningApps.first(where: { $0.localizedName == windowInfo.appName }) else {
                print("  App not found: \(windowInfo.appName)")
                results.append(WindowRestoreResult(appName: windowInfo.appName, windowTitle: windowInfo.windowTitle, status: .appNotFound))
                continue
            }
            
            switch axClient.windows(for: app.processIdentifier) {
            case .failure(let error):
                print("  AX windows failed for \(windowInfo.appName): \(error.rawValue)")
                results.append(WindowRestoreResult(appName: windowInfo.appName, windowTitle: windowInfo.windowTitle, status: .axFailure))
            case .success(let windowArray):
                var matched = false
                for windowElement in windowArray {
                    guard case .success(let title) = axClient.title(of: windowElement) else { continue }
                    if title == windowInfo.windowTitle || windowArray.count == 1 {
                        let status = self.setWindowFrame(windowElement, frame: targetFrame, debugName: "\(windowInfo.appName) — \(title)")
                        results.append(WindowRestoreResult(appName: windowInfo.appName, windowTitle: title, status: status))
                        matched = true
                        break
                    }
                }
                if !matched {
                    print("  Window skipped: \(windowInfo.windowTitle)")
                    results.append(WindowRestoreResult(appName: windowInfo.appName, windowTitle: windowInfo.windowTitle, status: .windowSkipped))
                }
            }
        }

        print("[RestoreResult] \(RestoreResult(layoutName: layout.name, windowsResults: results).summaryDescription)")
        return RestoreResult(layoutName: layout.name, windowsResults: results)
    }

    /// Вычисляет абсолютный targetFrame для окна при восстановлении.
    ///
    /// Алгоритм:
    /// 1. Если есть relativeFrame — пересчитываем через текущее положение экрана с нужным screenIndex.
    /// 2. Если screenIndex вышел за пределы (мониторов стало меньше) — ищем наиболее похожий экран
    ///    по разрешению среди доступных.
    /// 3. Fallback — используем абсолютный frame как есть (для старых лэйаутов).
    private func resolveTargetFrame(for windowInfo: WindowInfo, screens: [NSScreen]) -> CGRect {
        guard !screens.isEmpty else { return windowInfo.frame }

        guard let relativeFrame = windowInfo.relativeFrame else {
            return windowInfo.frame
        }

        func computeFrame(for screen: NSScreen) -> CGRect {
            CGRect(
                x: screen.frame.origin.x + relativeFrame.origin.x * screen.frame.width,
                y: screen.frame.origin.y + relativeFrame.origin.y * screen.frame.height,
                width: relativeFrame.width * screen.frame.width,
                height: relativeFrame.height * screen.frame.height
            )
        }

        func isCenterInside(frame: CGRect, screen: NSScreen) -> Bool {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            return screen.frame.contains(center)
        }

        // Prefer the stable display ID. NSScreen.screens order is not stable
        // across monitor reconnects, so an index alone can move every window
        // to a different display.
        let preferredIndex: Int
        if let savedScreenID = windowInfo.screenID,
           let stableIndex = screens.firstIndex(where: { getScreenID(for: $0) == savedScreenID }) {
            preferredIndex = stableIndex
            print("[WindowRestore] Window '\(windowInfo.appName)' matched saved display \(savedScreenID) at current index \(stableIndex)")
        } else {
            // Legacy layouts have no stable display ID.
            preferredIndex = min(max(windowInfo.screenIndex, 0), screens.count - 1)
            print("[WindowRestore] Window '\(windowInfo.appName)' using legacy display index \(preferredIndex)")
        }
        let preferredScreen = screens[preferredIndex]
        let preferredFrame = computeFrame(for: preferredScreen)

        if isCenterInside(frame: preferredFrame, screen: preferredScreen) {
             print("[WindowRestore] Window '\(windowInfo.appName)' → screen \(preferredIndex) (bounds check passed)")
            return preferredFrame
        }

        // Strategy 2: Find any screen whose bounds contain the window center
        for (index, screen) in screens.enumerated() {
            guard index != preferredIndex else { continue }
            let candidateFrame = computeFrame(for: screen)
            if isCenterInside(frame: candidateFrame, screen: screen) {
                print("[WindowRestore] Window '\(windowInfo.appName)' → screen \(index) (fallback: preferred screen \(preferredIndex) didn't contain center)")
                return candidateFrame
            }
        }

        // Strategy 3: Last resort — screen with maximum overlap
        var bestIndex = preferredIndex
        var bestOverlap: CGFloat = 0
        for (index, screen) in screens.enumerated() {
            let candidateFrame = computeFrame(for: screen)
            let intersection = screen.frame.intersection(candidateFrame)
            let area = intersection.width * intersection.height
            if area > bestOverlap {
                bestOverlap = area
                bestIndex = index
            }
        }
        let bestFrame = computeFrame(for: screens[bestIndex])
        print("[WindowRestore] Window '\(windowInfo.appName)' → screen \(bestIndex) (overlap fallback: \(String(format: "%.0f", bestOverlap)) px²)")
        return bestFrame
    }
    
    private func setWindowFrame(_ windowElement: AnyObject, frame: CGRect, debugName: String = "") -> WindowRestoreResult.WindowRestoreStatus {
        guard let coordinateConverter else { return .coordinateUnavailable }
        let expectedPosition = coordinateConverter.screenFrameToAXOrigin(frame)
        let expectedSize = frame.size

        let positionError = axClient.setPosition(expectedPosition, of: windowElement)
        guard positionError == .success else {
            print("[\(debugName)] position set failed: \(positionError.rawValue)")
            return .axFailure
        }
        let sizeError = axClient.setSize(expectedSize, of: windowElement)
        guard sizeError == .success else {
            print("[\(debugName)] size set failed: \(sizeError.rawValue)")
            return .axFailure
        }

        func readBack() -> AXOperationResult<(CGPoint, CGSize)> {
            let positionResult = axClient.position(of: windowElement)
            guard case .success(let position) = positionResult else {
                if case .failure(let error) = positionResult { return .failure(error) }
                return .failure(.failure)
            }
            let sizeResult = axClient.size(of: windowElement)
            guard case .success(let size) = sizeResult else {
                if case .failure(let error) = sizeResult { return .failure(error) }
                return .failure(.failure)
            }
            return .success((position, size))
        }

        guard case .success(let firstReadBack) = readBack() else {
            print("[\(debugName)] read-back failed")
            return .axFailure
        }
        let positionMatches = abs(firstReadBack.0.x - expectedPosition.x) <= 2 && abs(firstReadBack.0.y - expectedPosition.y) <= 2
        let sizeMatches = abs(firstReadBack.1.width - expectedSize.width) <= 2 && abs(firstReadBack.1.height - expectedSize.height) <= 2
        if positionMatches && sizeMatches { return .positionSet }

        // One bounded retry is allowed only for position drift caused by the size change.
        if !positionMatches {
            let retryError = axClient.setPosition(expectedPosition, of: windowElement)
            guard retryError == .success else { return .axFailure }
            guard case .success(let finalReadBack) = readBack() else { return .axFailure }
            let finalPositionMatches = abs(finalReadBack.0.x - expectedPosition.x) <= 2 && abs(finalReadBack.0.y - expectedPosition.y) <= 2
            let finalSizeMatches = abs(finalReadBack.1.width - expectedSize.width) <= 2 && abs(finalReadBack.1.height - expectedSize.height) <= 2
            if finalPositionMatches && finalSizeMatches { return .positionSet }
            if finalSizeMatches { return .appImposedClamp }
            return .appImposedClamp
        }

        return .appImposedClamp
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
