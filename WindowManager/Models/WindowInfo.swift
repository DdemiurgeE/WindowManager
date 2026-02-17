//
//  WindowInfo.swift
//  WindowManager
//
//  Created by Pavel Palnikov on 03.02.2026.
//


import Foundation
import CoreGraphics

struct WindowInfo: Codable, Identifiable {
    let id: UUID
    let appName: String
    let windowTitle: String
    let frame: CGRect
    let screenIndex: Int
    let timestamp: Date
    
    init(appName: String, windowTitle: String, frame: CGRect, screenIndex: Int) {
        self.id = UUID()
        self.appName = appName
        self.windowTitle = windowTitle
        self.frame = frame
        self.screenIndex = screenIndex
        self.timestamp = Date()
    }
}
