//
//  PermissionsService.swift
//  WindowManager
//
//  Created by Pavel Palnikov on 03.02.2026.
//


import Foundation
import AppKit
import ApplicationServices

class PermissionsService: ObservableObject {
    static let shared = PermissionsService()
    
    @Published var hasAccessibilityPermission = false
    @Published var hasScreenRecordingPermission = false
    
    init() {
        checkAllPermissions()
    }
    
    func checkAllPermissions() {
        DispatchQueue.main.async {
            self.hasAccessibilityPermission = self.checkAccessibilityPermission()
            self.hasScreenRecordingPermission = self.checkScreenRecordingPermission()
        }
    }
    
    func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // Открыть системные настройки
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    func checkScreenRecordingPermission() -> Bool {
        // Проверка через попытку получить список окон
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        // Если можем получить названия окон, значит есть разрешение
        for window in windowList {
            if let _ = window[kCGWindowName as String] as? String {
                return true
            }
        }
        return false
    }
    
    func requestScreenRecordingPermission() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
    
    func openSystemPreferences() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
    }
}