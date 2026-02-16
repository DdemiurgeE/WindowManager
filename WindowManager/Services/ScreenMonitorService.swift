//
//  ScreenMonitorService.swift
//  WindowManager
//
//  Created by Pavel Palnikov on 16.02.2026.
//


import Foundation
import AppKit
import Combine

class ScreenMonitorService: ObservableObject {
    static let shared = ScreenMonitorService()
    
    @Published var currentScreenConfiguration: ScreenConfiguration?
    
    private var cancellables = Set<AnyCancellable>()
    private var layoutStorageService: LayoutStorageService?
    private var windowService: WindowService?
    
    private init() {
        setupScreenMonitoring()
        updateCurrentScreenConfiguration()
    }
    
    func setup(layoutStorage: LayoutStorageService, windowService: WindowService) {
        self.layoutStorageService = layoutStorage
        self.windowService = windowService
    }
    
    private func setupScreenMonitoring() {
        // Подписываемся на изменения конфигурации экранов
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleScreenConfigurationChange()
            }
            .store(in: &cancellables)
    }
    
    private func handleScreenConfigurationChange() {
        print("=== Screen configuration changed ===")
        
        let newConfiguration = getCurrentScreenConfiguration()
        
        // Проверяем, действительно ли конфигурация изменилась
        guard newConfiguration != currentScreenConfiguration else {
            print("Screen configuration unchanged, skipping")
            return
        }
        
        print("Old configuration: \(currentScreenConfiguration?.screenIDs ?? [])")
        print("New configuration: \(newConfiguration.screenIDs)")
        
        currentScreenConfiguration = newConfiguration
        
        // Автоматически применяем подходящий layout
        applyLayoutForCurrentConfiguration()
    }
    
    func getCurrentScreenConfiguration() -> ScreenConfiguration {
        let screens = NSScreen.screens
        let screenIDs = screens.map { getScreenID(for: $0) }
        return ScreenConfiguration(screenIDs: screenIDs)
    }
    
    private func getScreenID(for screen: NSScreen) -> String {
        // Используем deviceDescription для получения уникального ID монитора
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "screen_\(screenNumber.intValue)"
        }
        
        // Fallback: используем размер и позицию экрана
        let frame = screen.frame
        return "screen_\(Int(frame.width))x\(Int(frame.height))_\(Int(frame.origin.x))_\(Int(frame.origin.y))"
    }
    
    private func applyLayoutForCurrentConfiguration() {
        guard let currentConfig = currentScreenConfiguration,
              let layoutStorage = layoutStorageService,
              let windowService = windowService else {
            return
        }
        
        // Ищем последний использованный layout для текущей конфигурации
        let matchingLayouts = layoutStorage.layouts.filter { layout in
            guard let layoutConfig = layout.screenConfiguration else { return false }
            return layoutConfig == currentConfig
        }
        
        // Сортируем по дате последнего использования
        let sortedLayouts = matchingLayouts.sorted { layout1, layout2 in
            guard let date1 = layout1.lastUsed, let date2 = layout2.lastUsed else {
                return layout1.lastUsed != nil
            }
            return date1 > date2
        }
        
        // Применяем самый свежий layout
        if let layoutToApply = sortedLayouts.first {
            print("Auto-applying layout: \(layoutToApply.name)")
            
            // Небольшая задержка для стабилизации системы после подключения монитора
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                windowService.restoreLayout(layoutToApply)
                layoutStorage.markLayoutAsUsed(layoutToApply)
                
                // Отправляем уведомление пользователю
                self?.showNotification(layoutName: layoutToApply.name)
            }
        } else {
            print("No matching layout found for current screen configuration")
        }
    }
    
    private func showNotification(layoutName: String) {
        let notification = NSUserNotification()
        notification.title = "Window Manager"
        notification.informativeText = "Layout '\(layoutName)' applied automatically"
        notification.soundName = nil
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    func updateCurrentScreenConfiguration() {
        currentScreenConfiguration = getCurrentScreenConfiguration()
        print("Current screen configuration: \(currentScreenConfiguration?.screenIDs ?? [])")
    }
}