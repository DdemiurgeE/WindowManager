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
        guard statusItem == nil else {
            updateMenu()
            return
        }
        
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
        
        // 0. Snap Active Window submenu (right-click quick access)
        let snapMenuItem = NSMenuItem(title: "Snap Active Window", action: nil, keyEquivalent: "")
        snapMenuItem.submenu = createSnapSubmenu()
        menu.addItem(snapMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
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
        
        print("StatusBarService: Applying layout")
        windowService?.restoreLayout(layout)
        try? layoutStorage?.markLayoutAsUsed(layout)
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
    
    // MARK: - Snap Active Window
    
    private func createSnapSubmenu() -> NSMenu {
        let submenu = NSMenu(title: "Snap Active Window")
        
        // Halves
        let halvesHeader = NSMenuItem(title: "Halves", action: nil, keyEquivalent: "")
        halvesHeader.isEnabled = false
        submenu.addItem(halvesHeader)
        
        submenu.addItem(NSMenuItem(title: "Left Half", action: #selector(snapLeftHalf), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Right Half", action: #selector(snapRightHalf), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Top Half", action: #selector(snapTopHalf), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Bottom Half", action: #selector(snapBottomHalf), keyEquivalent: ""))
        
        submenu.addItem(NSMenuItem.separator())
        
        // Quarters
        let quartersHeader = NSMenuItem(title: "Quarters", action: nil, keyEquivalent: "")
        quartersHeader.isEnabled = false
        submenu.addItem(quartersHeader)
        
        submenu.addItem(NSMenuItem(title: "Top Left Quarter", action: #selector(snapTopLeftQuarter), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Top Right Quarter", action: #selector(snapTopRightQuarter), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Bottom Left Quarter", action: #selector(snapBottomLeftQuarter), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Bottom Right Quarter", action: #selector(snapBottomRightQuarter), keyEquivalent: ""))
        
        submenu.addItem(NSMenuItem.separator())
        
        // Thirds
        let thirdsHeader = NSMenuItem(title: "Thirds", action: nil, keyEquivalent: "")
        thirdsHeader.isEnabled = false
        submenu.addItem(thirdsHeader)
        
        submenu.addItem(NSMenuItem(title: "Left Third", action: #selector(snapLeftThird), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Middle Third", action: #selector(snapMiddleThird), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Right Third", action: #selector(snapRightThird), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Left Two Thirds", action: #selector(snapLeftTwoThirds), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Right Two Thirds", action: #selector(snapRightTwoThirds), keyEquivalent: ""))
        
        submenu.addItem(NSMenuItem.separator())
        
        // Full
        submenu.addItem(NSMenuItem(title: "Fill Usable Area", action: #selector(snapFillUsableArea), keyEquivalent: ""))
        
        // Set target for all action items
        for item in submenu.items where item.action != nil {
            item.target = self
        }
        
        return submenu
    }
    
    private func snapActiveWindow(to zone: SnapZone) {
        guard let windowService else { return }
        
        // Get the frontmost application's focused window
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            print("StatusBarService: No valid frontmost app")
            return
        }
        
        // Get current screen
        let currentScreen = NSScreen.main ?? NSScreen.screens.first
        guard let screen = currentScreen else {
            print("StatusBarService: No screen found")
            return
        }
        
        // Apply snap position
        windowService.snapActiveWindow(to: zone, on: screen)
    }
    
    @objc private func snapLeftHalf() { snapActiveWindow(to: .leftHalf) }
    @objc private func snapRightHalf() { snapActiveWindow(to: .rightHalf) }
    @objc private func snapTopHalf() { snapActiveWindow(to: .topHalf) }
    @objc private func snapBottomHalf() { snapActiveWindow(to: .bottomHalf) }
    
    @objc private func snapTopLeftQuarter() { snapActiveWindow(to: .topLeft) }
    @objc private func snapTopRightQuarter() { snapActiveWindow(to: .topRight) }
    @objc private func snapBottomLeftQuarter() { snapActiveWindow(to: .bottomLeft) }
    @objc private func snapBottomRightQuarter() { snapActiveWindow(to: .bottomRight) }
    
    @objc private func snapLeftThird() { snapActiveWindow(to: .leftThird) }
    @objc private func snapMiddleThird() { snapActiveWindow(to: .middleThird) }
    @objc private func snapRightThird() { snapActiveWindow(to: .rightThird) }
    @objc private func snapLeftTwoThirds() { snapActiveWindow(to: .leftTwoThirds) }
    @objc private func snapRightTwoThirds() { snapActiveWindow(to: .rightTwoThirds) }
    
    @objc private func snapFillUsableArea() { snapActiveWindow(to: .maximize) }
    
    @objc private func quitApp() {
        print("StatusBarService: quitApp called")
        NSApplication.shared.terminate(nil)
    }
}
