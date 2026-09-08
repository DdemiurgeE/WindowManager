import SwiftUI
import Sparkle

@main
struct WindowManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowService = WindowService()
    @StateObject private var permissionsService = PermissionsService()
    @StateObject private var layoutStorage = LayoutStorageService()
    @State private var windowID = UUID()
    
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(windowService)
                .environmentObject(permissionsService)
                .environmentObject(layoutStorage)
                .frame(minWidth: 600, minHeight: 400)
                .onAppear {
                    setupServices()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    UpdateService.shared.checkForUpdates()
                }
            }
        }
        
        Settings {
            PermissionsView()
                .environmentObject(permissionsService)
        }
    }
    
    private func setupServices() {
        // Инициализируем StatusBar
        StatusBarService.shared.setup(
            windowService: windowService,
            layoutStorage: layoutStorage
        )
        
        // Инициализируем мониторинг экранов
        ScreenMonitorService.shared.setup(
            layoutStorage: layoutStorage,
            windowService: windowService
        )
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        PermissionsService.shared.checkAllPermissions()
        UpdateService.shared.start()
        
        // Сохраняем ссылку на главное окно
        DispatchQueue.main.async {
            self.mainWindow = NSApp.windows.first { window in
                window.contentViewController != nil
            }
        }
        
        // Раскомментируйте строку ниже, если хотите скрыть иконку из Dock:
        // NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Приложение продолжает работать в Menu Bar после закрытия окна
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openOrCreateMainWindow()
        }
        return true
    }
    
    func openOrCreateMainWindow() {
        // Ищем существующее окно
        if let window = mainWindow, !window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Ищем любое окно приложения
        for window in NSApp.windows {
            if window.contentViewController != nil {
                mainWindow = window
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
    }
}
