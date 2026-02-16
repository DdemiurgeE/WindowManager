//
//  StatusBarService.swift
//  WindowManager
//
//  Created by Pavel Palnikov on 16.02.2026.
//


import AppKit
import SwiftUI

class StatusBarService: NSObject {
    static let shared = StatusBarService()
    
    private var statusItem: NSStatusItem?
    private var windowService: WindowService?
    private var layoutStorage: LayoutStorageService?
    
    func setup(windowService: WindowService, layoutStorage: LayoutStorageService) {
        self.windowService = windowService
        self.layoutStorage = layoutStorage
        
        // Создаем Status Item в системном меню-баре
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Используем системную иконку для начала, позже заменим на кастомную
            button.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Window Manager")
            button.image?.isTemplate = true // Позволяет иконке менять цвет под тему (темная/светлая)
        }
        
        updateMenu()
    }
    
    func updateMenu() {
        let menu = NSMenu()
        
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
        
        statusItem?.menu = menu
    }
    
    @objc private func applyLayout(_ sender: NSMenuItem) {
        if let layout = sender.representedObject as? Layout {
            windowService?.restoreLayout(layout)
            layoutStorage?.markLayoutAsUsed(layout)
        }
    }
    
    @objc private func saveCurrentLayout() {
        // Показываем окно для ввода имени
        openMainWindow()
        // Можно добавить NotificationCenter для вызова алерта в ContentView
        NotificationCenter.default.post(name: NSNotification.Name("ShowSaveLayoutAlert"), object: nil)
    }
    
    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}