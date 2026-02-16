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
                    // Передаем зависимости в AppDelegate, если нужно,
                    // или инициализируем сервисы здесь
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
        
        // Инициализируем мониторинг экранов (авто-применение)
        ScreenMonitorService.shared.setup(
            layoutStorage: layoutStorage,
            windowService: windowService
        )
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Проверка разрешений при запуске
        PermissionsService.shared.checkAllPermissions()
        
        // Если вы хотите, чтобы приложение работало ТОЛЬКО в Menu Bar (без иконки в Dock),
        // раскомментируйте строку ниже:
        // NSApp.setActivationPolicy(.accessory)
    }
    
    // Добавим метод, чтобы приложение не закрывалось полностью при закрытии окна
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
