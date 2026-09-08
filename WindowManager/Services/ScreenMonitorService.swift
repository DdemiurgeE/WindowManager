//
//  ScreenMonitorService.swift
//  WindowManager
//
//  Created by Pavel Palnikov on 16.02.2026.
//


import Foundation
import AppKit
import Combine
import UserNotifications

class ScreenMonitorService: ObservableObject {
    static let shared = ScreenMonitorService()
    
    private let screenChangeDebounceDelay: TimeInterval = 0.5
    private let screenStabilityPollInterval: TimeInterval = 0.25
    private let requiredStableScreenReadings = 3
    private let screenStabilityMaxWait: TimeInterval = 10.0

    @Published var currentScreenConfiguration: ScreenConfiguration?
    
    private var cancellables = Set<AnyCancellable>()
    private var layoutStorageService: LayoutStorageService?
    private var windowService: WindowService?
    private var pendingRestoreWorkItem: DispatchWorkItem?
    private var pendingRestoreID: UUID?
    private var restoreLog: [RestoreEvent] = []
    private let maxRestoreLogEntries = 20
    
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
            .debounce(for: .seconds(screenChangeDebounceDelay), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleScreenConfigurationChange()
            }
            .store(in: &cancellables)
    }
    
    private func handleScreenConfigurationChange() {
        print("[ScreenMonitor] Screen configuration change event received")
        cancelPendingRestore(reason: "new screen configuration event")
        
        let newConfiguration = getCurrentScreenConfiguration()
        
        // Проверяем, действительно ли конфигурация изменилась
        guard newConfiguration != currentScreenConfiguration else {
            print("[ScreenMonitor] Screen configuration unchanged, skipping")
            return
        }
        
        print("[ScreenMonitor] Old configuration: \(currentScreenConfiguration?.screenIDs ?? [])")
        print("[ScreenMonitor] New configuration: \(newConfiguration.screenIDs)")
        
        currentScreenConfiguration = newConfiguration
        
        // Автоматически применяем подходящий layout
        scheduleAutoApplyAfterScreenStabilizes()
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
    
    private func scheduleAutoApplyAfterScreenStabilizes() {
        // Проверяем, включен ли auto-apply
        let autoApplyEnabled = UserDefaults.standard.object(forKey: "autoApplyEnabled") as? Bool ?? true
        guard autoApplyEnabled else {
            print("[ScreenMonitor] Auto-apply is disabled, skipping")
            return
        }
        
        guard let layoutStorage = layoutStorageService,
              let windowService = windowService else {
            print("[ScreenMonitor] Auto-apply services are not ready, skipping")
            return
        }
        
        print("[ScreenMonitor] Waiting for stable screen configuration")

        let startedAt = Date()
        let lastObservedConfiguration = getCurrentScreenConfiguration()
        let stableReadings = 1
        let restoreID = UUID()
        let workItem = DispatchWorkItem { [weak self, weak layoutStorage, weak windowService] in
            self?.waitForStableScreenConfiguration(
                restoreID: restoreID,
                startedAt: startedAt,
                lastObservedConfiguration: lastObservedConfiguration,
                stableReadings: stableReadings,
                layoutStorage: layoutStorage,
                windowService: windowService
            )
        }

        pendingRestoreID = restoreID
        pendingRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + screenStabilityPollInterval, execute: workItem)
    }

    private func waitForStableScreenConfiguration(
        restoreID: UUID,
        startedAt: Date,
        lastObservedConfiguration: ScreenConfiguration,
        stableReadings: Int,
        layoutStorage: LayoutStorageService?,
        windowService: WindowService?
    ) {
        guard pendingRestoreID == restoreID else {
            print("[ScreenMonitor] Ignoring stale pending restore")
            return
        }

        guard let layoutStorage, let windowService else {
            print("[ScreenMonitor] Auto-apply services disappeared, skipping")
            self.pendingRestoreWorkItem = nil
            return
        }

        let latestConfiguration = getCurrentScreenConfiguration()
        let nextStableReadings = latestConfiguration == lastObservedConfiguration ? stableReadings + 1 : 1
        let elapsed = Date().timeIntervalSince(startedAt)

        print("[ScreenMonitor] Stability check: ids=\(latestConfiguration.screenIDs), stableReadings=\(nextStableReadings)/\(requiredStableScreenReadings), elapsed=\(String(format: "%.2f", elapsed))s")

        if nextStableReadings >= requiredStableScreenReadings {
            print("[ScreenMonitor] Stable screen configuration reached")
            currentScreenConfiguration = latestConfiguration
            self.pendingRestoreID = nil
            self.pendingRestoreWorkItem = nil
            applyLayout(for: latestConfiguration, layoutStorage: layoutStorage, windowService: windowService)
            return
        }

        if elapsed >= screenStabilityMaxWait {
            print("[ScreenMonitor] Screen stability wait timed out; applying latest observed configuration")
            currentScreenConfiguration = latestConfiguration
            self.pendingRestoreID = nil
            self.pendingRestoreWorkItem = nil
            applyLayout(for: latestConfiguration, layoutStorage: layoutStorage, windowService: windowService)
            return
        }

        let nextWorkItem = DispatchWorkItem { [weak self, weak layoutStorage, weak windowService] in
            self?.waitForStableScreenConfiguration(
                restoreID: restoreID,
                startedAt: startedAt,
                lastObservedConfiguration: latestConfiguration,
                stableReadings: nextStableReadings,
                layoutStorage: layoutStorage,
                windowService: windowService
            )
        }

        self.pendingRestoreWorkItem = nextWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + screenStabilityPollInterval, execute: nextWorkItem)
    }

    private func applyLayout(for currentConfig: ScreenConfiguration, layoutStorage: LayoutStorageService, windowService: WindowService) {
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
            print("[ScreenMonitor] Auto-applying layout: \(layoutToApply.name)")
            appendRestoreEvent(RestoreEvent(
                layoutName: layoutToApply.name,
                screenConfiguration: currentConfig,
                status: .started,
                windowsTotal: layoutToApply.windows.count
            ))
            print("[ScreenMonitor] Restore started")
            let restoreResult = windowService.restoreLayout(layoutToApply)
            layoutStorage.markLayoutAsUsed(layoutToApply)
            print("[ScreenMonitor] Restore finished: \(restoreResult.summaryDescription)")
            appendRestoreEvent(RestoreEvent(
                layoutName: layoutToApply.name,
                screenConfiguration: currentConfig,
                status: .completed,
                windowsTotal: layoutToApply.windows.count,
                windowsRestored: restoreResult.windowsRestored
            ))
            
            // Отправляем уведомление пользователю
            showNotification(layoutName: layoutToApply.name, summary: restoreResult.summaryDescription)
        } else {
            print("[ScreenMonitor] No matching layout found for current screen configuration")
            appendRestoreEvent(RestoreEvent(
                layoutName: "",
                screenConfiguration: currentConfig,
                status: .noMatch,
                windowsTotal: 0
            ))
        }
    }

    private func cancelPendingRestore(reason: String) {
        guard let pendingRestoreWorkItem else { return }
        pendingRestoreWorkItem.cancel()
        self.pendingRestoreID = nil
        self.pendingRestoreWorkItem = nil
        print("[ScreenMonitor] Cancelled pending restore: \(reason)")
        appendRestoreEvent(RestoreEvent(
            layoutName: "",
            screenConfiguration: currentScreenConfiguration,
            status: .cancelled,
            windowsTotal: 0
        ))
    }
    
    private func showNotification(layoutName: String, summary: String) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.deliverNotification(center: center, layoutName: layoutName, summary: summary)

            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        print("Notification authorization error: \(error)")
                        return
                    }

                    guard granted else {
                        print("Notification permission not granted")
                        return
                    }

                    self.deliverNotification(center: center, layoutName: layoutName, summary: summary)
                }

            case .denied:
                // Пользователь запретил уведомления — тихо пропускаем
                print("Notification permission denied")

            @unknown default:
                print("Unknown notification authorization status")
            }
        }
    }

    private func deliverNotification(center: UNUserNotificationCenter, layoutName: String, summary: String) {
        let content = UNMutableNotificationContent()
        content.title = "Window Manager"
        content.body = "Layout '\(layoutName)' applied — \(summary)"
        // Без звука, как и раньше
        // content.sound = .default

        let request = UNNotificationRequest(
            identifier: "window_manager.layout_applied",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                print("Failed to deliver notification: \(error)")
            }
        }
    }

    func updateCurrentScreenConfiguration() {
        currentScreenConfiguration = getCurrentScreenConfiguration()
        print("Current screen configuration: \(currentScreenConfiguration?.screenIDs ?? [])")
    }

    func getRestoreLog() -> [RestoreEvent] {
        restoreLog
    }

    private func appendRestoreEvent(_ event: RestoreEvent) {
        restoreLog.append(event)
        if restoreLog.count > maxRestoreLogEntries {
            restoreLog.removeFirst()
        }
        print("[RestoreLog] \(event.timestamp.formatted()) \(event.status.rawValue): \(event.layoutName) (\(event.windowsRestored)/\(event.windowsTotal) windows, config: \(event.screenConfiguration?.screenIDs ?? []))")
    }
}
