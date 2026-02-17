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
        
        // 3. Пункт "Auto-apply Layouts"
        let autoApplyEnabled = UserDefaults.standard.object(forKey: "autoApplyEnabled") as? Bool ?? true
        let autoApplyItem = NSMenuItem(title: "Auto-apply Layouts", action: #selector(toggleAutoApply), keyEquivalent: "")
        autoApplyItem.target = self
        autoApplyItem.state = autoApplyEnabled ? .on : .off
        menu.addItem(autoApplyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 4. Пункт "Open Window"
        let openWindowItem = NSMenuItem(title: "Open Window", action: #selector(openMainWindow), keyEquivalent: "o")
        openWindowItem.target = self
        menu.addItem(openWindowItem)
        
        // 5. Пункт "Quit"
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
    
    @objc private func toggleAutoApply() {
        print("StatusBarService: toggleAutoApply called")
        let currentValue = UserDefaults.standard.object(forKey: "autoApplyEnabled") as? Bool ?? true
        let newValue = !currentValue
        UserDefaults.standard.set(newValue, forKey: "autoApplyEnabled")
        print("StatusBarService: Auto-apply set to \(newValue)")
        
        // Обновляем меню для отображения нового состояния
        updateMenu()
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
        
        // Ищем все окна приложения
        let appWindows = NSApp.windows.filter { window in
            return window.canBecomeKey &&
                   window.contentViewController != nil
        }
        
        if let window = appWindows.first {
            // Если окно свернуто, разворачиваем его
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            // Делаем окно активным
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Если окон нет, вызываем метод AppDelegate
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.openOrCreateMainWindow()
            }
        }
    }
    
    @objc private func quitApp() {
        print("StatusBarService: quitApp called")
        NSApplication.shared.terminate(nil)
    }
}
