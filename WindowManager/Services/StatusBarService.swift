import AppKit
import SwiftUI

class StatusBarService: NSObject, NSMenuDelegate {
    static let shared = StatusBarService()
    
    private var statusItem: NSStatusItem?
    private var windowService: WindowService?
    private var layoutStorage: LayoutStorageService?
    private var menu: NSMenu?
    
    func setup(windowService: WindowService, layoutStorage: LayoutStorageService) {
        self.windowService = windowService
        self.layoutStorage = layoutStorage
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Используем системную иконку. Вы можете заменить её на свою "StatusBarIcon" в Assets
            button.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Window Manager")
            button.image?.isTemplate = true
        }
        
        // Создаем меню и устанавливаем делегат
        menu = NSMenu()
        menu?.delegate = self
        statusItem?.menu = menu
        
        updateMenu()
    }
    
    func updateMenu() {
        guard let menu = menu else { return }
        
        // Очищаем существующее меню
        menu.removeAllItems()
        
        // 1. Список сохраненных Layout
        if let layouts = layoutStorage?.layouts, !layouts.isEmpty {
            let layoutsHeader = NSMenuItem(title: "Saved Layouts", action: nil, keyEquivalent: "")
            layoutsHeader.isEnabled = false
            menu.addItem(layoutsHeader)
            
            for layout in layouts {
                let item = NSMenuItem(title: layout.name, action: #selector(applyLayout(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = layout
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
        }
        
        // 2. Пункт "Save Current Layout..."
        let saveItem = NSMenuItem(title: "Save Current Layout...", action: #selector(saveCurrentLayout), keyEquivalent: "s")
        saveItem.target = self
        menu.addItem(saveItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Пункт "Open Window"
        let openWindowItem = NSMenuItem(title: "Open Window", action: #selector(openMainWindow), keyEquivalent: "o")
        openWindowItem.target = self
        menu.addItem(openWindowItem)
        
        // 4. Пункт "Quit"
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    // MARK: - NSMenuDelegate
    
    func menuWillOpen(_ menu: NSMenu) {
        // Обновляем меню каждый раз перед открытием
        updateMenu()
    }
    
    @objc private func applyLayout(_ sender: NSMenuItem) {
        print("StatusBarService: applyLayout called")
        guard let layout = sender.representedObject as? Layout else {
            print("StatusBarService: No layout found in representedObject")
            return
        }
        
        print("StatusBarService: Applying layout '\(layout.name)'")
        windowService?.restoreLayout(layout)
        layoutStorage?.markLayoutAsUsed(layout)
    }
    
    @objc private func saveCurrentLayout() {
        print("StatusBarService: saveCurrentLayout called")
        openMainWindow()
        
        // Небольшая задержка, чтобы окно успело открыться
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: NSNotification.Name("ShowSaveLayoutAlert"), object: nil)
        }
    }
    
    @objc private func openMainWindow() {
        print("StatusBarService: openMainWindow called")
        NSApp.activate(ignoringOtherApps: true)
        
        // Ищем главное окно приложения
        for window in NSApp.windows {
            if window.title.contains("Window Manager") || window.contentViewController != nil {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
        
        // Если окно не найдено, пытаемся открыть первое доступное
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc private func quitApp() {
        print("StatusBarService: quitApp called")
        NSApplication.shared.terminate(nil)
    }
}
