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
            guard app.activationPolicy == .regular else { continue }
            
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
    
    private func getWindowInfo(from windowElement: AXUIElement, appName: String, screens: [NSScreen]) -> WindowInfo? {
        var titleRef: CFTypeRef?
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        
        // Получаем заголовок окна
        AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String ?? "Untitled"
        
        // Получаем позицию
        AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionRef)
        var position = CGPoint.zero
        if let positionValue = positionRef {
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        }
        
        // Получаем размер
        AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef)
        var size = CGSize.zero
        if let sizeValue = sizeRef {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }
        
        // Санитизация: проверяем, что координаты и размеры в разумных пределах
        // Игнорируем окна с нулевым или слишком маленьким размером
        guard size.width >= 50 && size.height >= 50 else {
            return nil
        }
        
        // Проверяем, что координаты не выходят за пределы всех экранов
        // Находим общие границы всех экранов
        var minX: CGFloat = 0
        var minY: CGFloat = 0
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        
        for screen in screens {
            let frame = screen.frame
            minX = min(minX, frame.origin.x)
            minY = min(minY, frame.origin.y)
            maxX = max(maxX, frame.origin.x + frame.width)
            maxY = max(maxY, frame.origin.y + frame.height)
        }
        
        // Если окно полностью за пределами всех экранов, игнорируем его
        let windowMaxX = position.x + size.width
        let windowMaxY = position.y + size.height
        
        if windowMaxX < minX || position.x > maxX || windowMaxY < minY || position.y > maxY {
            print("Skipping window '\(title)' - outside screen bounds")
            return nil
        }
        
        // Создаем frame с санитизированными значениями
        let sanitizedFrame = CGRect(
            x: position.x,
            y: position.y,
            width: max(size.width, 100),  // Минимальная ширина
            height: max(size.height, 100) // Минимальная высота
        )
        
        // Определяем индекс экрана
        let screenIndex = self.getScreenIndex(for: sanitizedFrame, screens: screens)
        
        return WindowInfo(appName: appName, windowTitle: title, frame: sanitizedFrame, screenIndex: screenIndex)
    }
    
    private func getScreenIndex(for frame: CGRect, screens: [NSScreen]) -> Int {
        for (index, screen) in screens.enumerated() {
            if screen.frame.intersects(frame) {
                return index
            }
        }
        return 0
    }
    
    func restoreLayout(_ layout: Layout) {
        guard PermissionsService.shared.checkAccessibilityPermission() else {
            print("No accessibility permission")
            return
        }
        
        let runningApps = NSWorkspace.shared.runningApplications
        let screens = NSScreen.screens
        
        print("=== Restoring layout: \(layout.name) ===")
        print("Available screens: \(screens.count)")
        for (index, screen) in screens.enumerated() {
            print("Screen \(index): \(screen.frame)")
        }
        
        for windowInfo in layout.windows {
            print("\nRestoring: \(windowInfo.appName) - \(windowInfo.windowTitle)")
            print("Target frame: \(windowInfo.frame)")
            print("Target screen: \(windowInfo.screenIndex)")
            // Находим приложение
            guard let app = runningApps.first(where: { $0.localizedName == windowInfo.appName }) else {
                print("App not found: \(windowInfo.appName)")
                continue
            }
            
            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            
            let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            
            if result == .success, let windowArray = windowsRef as? [AXUIElement] {
                // Ищем окно по заголовку
                for windowElement in windowArray {
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
                    let title = titleRef as? String ?? ""
                    
                    if title == windowInfo.windowTitle || windowArray.count == 1 {
                        // Восстанавливаем позицию и размер
                        self.setWindowFrame(windowElement, frame: windowInfo.frame)
                        break
                    }
                }
            }
        }
    }
    
    private func setWindowFrame(_ windowElement: AXUIElement, frame: CGRect) {
        // 1. Сначала устанавливаем размер
        var size = frame.size
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue)
        }
        
        // Небольшая пауза, чтобы система успела обработать изменение размера
        usleep(50000) // 50ms
        
        // 2. Устанавливаем позицию
        var position = frame.origin
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            let result = AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, positionValue)
            
            // Если не удалось с первого раза, пробуем еще раз
            if result != .success {
                print("Failed to set position on first attempt, retrying...")
                usleep(100000) // 100ms
                AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, positionValue)
            }
        }
        
        // 3. Финальная проверка и коррекция (для упрямых окон)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            var currentPositionRef: CFTypeRef?
            AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &currentPositionRef)
            
            if let currentPosValue = currentPositionRef {
                var currentPos = CGPoint.zero
                AXValueGetValue(currentPosValue as! AXValue, .cgPoint, &currentPos)
                
                // Если позиция отличается больше чем на 10 пикселей, пробуем еще раз
                let deltaX = abs(currentPos.x - position.x)
                let deltaY = abs(currentPos.y - position.y)
                
                if deltaX > 10 || deltaY > 10 {
                    print("Window drifted by (\(deltaX), \(deltaY)), correcting...")
                    if let posValue = AXValueCreate(.cgPoint, &position) {
                        AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, posValue)
                    }
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
