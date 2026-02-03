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
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        
        Settings {
            PermissionsView()
                .environmentObject(permissionsService)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Проверка разрешений при запуске
        PermissionsService.shared.checkAllPermissions()
    }
}
