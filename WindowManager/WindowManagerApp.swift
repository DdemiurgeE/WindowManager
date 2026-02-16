import SwiftUI

@main
struct WindowManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowService = WindowService()
    @StateObject private var permissionsService = PermissionsService()
    @StateObject private var layoutStorage = LayoutStorageService()
    
    var body: some Scene {
        WindowGroup {
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        PermissionsService.shared.checkAllPermissions()
        
        // Раскомментируйте строку ниже, если хотите скрыть иконку из Dock:
        // NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Приложение продолжает работать в Menu Bar после закрытия окна
        return false
    }
}
