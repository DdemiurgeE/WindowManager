import Foundation
import AppKit
import ApplicationServices
import Combine

class WindowService: ObservableObject {
    @Published var currentWindows: [WindowInfo] = []
    @Published var isCapturing = false
    
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
    
    /// Высота главного экрана — база системы координат AX/Quartz.
    /// NSScreen.main — экран с активной строкой меню.
    private var mainScreenHeight: CGFloat {
        (NSScreen.main ?? NSScreen.screens[0]).frame.height
    }

    /// Конвертирует NSScreen-frame окна в AX/Quartz origin (top-left угол окна).
    /// NSScreen: origin = нижний-левый угол NSScreen.main, Y вверх.
    /// AX/Quartz: origin = верхний-левый угол NSScreen.main, Y вниз.
    ///
    /// Формула: axY = mainScreenHeight - screenY - windowHeight
    private func screenFrameToAXOrigin(_ frame: CGRect) -> CGPoint {
        let h = mainScreenHeight
        return CGPoint(
            x: frame.origin.x,
            y: h - frame.origin.y - frame.size.height
        )
    }

    /// Конвертирует AX/Quartz позицию + размер в NSScreen-frame.
    private func axOriginToScreenFrame(axOrigin: CGPoint, size: CGSize) -> CGRect {
        let h = mainScreenHeight
        return CGRect(
            x: axOrigin.x,
            y: h - axOrigin.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func getWindowInfo(from windowElement: AXUIElement, appName: String, screens: [NSScreen]) -> WindowInfo? {
        var titleRef: CFTypeRef?
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        
        // Получаем заголовок окна
        AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String ?? "Untitled"
        
        // Получаем позицию в пространстве AX/Quartz:
        //   origin = верхний-левый угол ГЛАВНОГО экрана (NSScreen.main), Y растёт вниз.
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

        // Конвертируем AX/Quartz → NSScreen (абсолютные координаты)
        let screenFrame = axOriginToScreenFrame(axOrigin: axPosition, size: CGSize(width: max(size.width, 100), height: max(size.height, 100)))

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
        
        let runningApps = NSWorkspace.shared.runningApplications
        let screens = NSScreen.screens
        
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
            
            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            
            let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            
            if result == .success, let windowArray = windowsRef as? [AXUIElement] {
                var matched = false
                for windowElement in windowArray {
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
                    let title = titleRef as? String ?? ""
                    
                    if title == windowInfo.windowTitle || windowArray.count == 1 {
                        self.setWindowFrame(windowElement, frame: targetFrame, debugName: "\(windowInfo.appName) — \(title)")
                        results.append(WindowRestoreResult(appName: windowInfo.appName, windowTitle: title, status: .positionSet))
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
    
    private func setWindowFrame(_ windowElement: AXUIElement, frame: CGRect, debugName: String = "") {
        let axPosition = screenFrameToAXOrigin(frame)
        var size = frame.size
        var pos = axPosition

        // Устанавливаем позицию и размер дважды — сначала позицию, потом размер, потом снова позицию.
        // Это нужно потому что некоторые приложения (например Finder) клипают размер,
        // что смещает позицию окна. Повторная установка позиции после размера это исправляет.

        // 1. Позиция (первый раз — чтобы окно оказалось в нужном месте до изменения размера)
        if let posValue = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, posValue)
        }

        usleep(50_000) // 50ms

        // 2. Размер
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue)
        }

        usleep(50_000) // 50ms

        // 3. Позиция повторно — на случай если изменение размера сдвинуло окно
        if let posValue = AXValueCreate(.cgPoint, &pos) {
            let result = AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, posValue)
            if result != .success {
                usleep(100_000)
                AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, posValue)
            }
        }

        // 4. Проверка через 0.5с
        let capturedElement = windowElement
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            var currentPosRef: CFTypeRef?
            AXUIElementCopyAttributeValue(capturedElement, kAXPositionAttribute as CFString, &currentPosRef)
            guard let currentPosValue = currentPosRef else { return }

            var currentPos = CGPoint.zero
            AXValueGetValue(currentPosValue as! AXValue, .cgPoint, &currentPos)

            let deltaX = abs(currentPos.x - axPosition.x)
            let deltaY = abs(currentPos.y - axPosition.y)

            if deltaX > 2 || deltaY > 2 {
                print("⚠️ [\(debugName)] Drift (\(Int(deltaX)),\(Int(deltaY))), correcting...")
                var corrPos = axPosition
                if let posValue = AXValueCreate(.cgPoint, &corrPos) {
                    AXUIElementSetAttributeValue(capturedElement, kAXPositionAttribute as CFString, posValue)
                }
            }
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
