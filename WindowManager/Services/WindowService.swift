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
        
        let frame = CGRect(origin: position, size: size)
        
        // Определяем индекс экрана
        let screenIndex = self.getScreenIndex(for: frame, screens: screens)
        
        return WindowInfo(appName: appName, windowTitle: title, frame: frame, screenIndex: screenIndex)
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
        // Устанавливаем позицию
        var position = frame.origin
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, positionValue)
        }
        
        // Устанавливаем размер
        var size = frame.size
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue)
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
}
