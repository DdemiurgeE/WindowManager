//
//  WindowInfo.swift
//  WindowManager
//

import Foundation
import CoreGraphics

struct WindowInfo: Codable, Identifiable {
    let id: UUID
    let appName: String
    let windowTitle: String

    /// Абсолютный frame в пространстве NSScreen.
    /// Используется как fallback для старых лэйаутов без relativeFrame.
    let frame: CGRect

    /// Позиция окна относительно его экрана (нормализованная, 0.0–1.0).
    /// Корректно восстанавливает позиции даже если macOS
    /// изменила абсолютное расположение мониторов при переподключении.
    let relativeFrame: CGRect?

    /// Stable display identifier captured from NSScreenNumber.
    /// Optional for backward compatibility with layouts saved before v2.4.
    let screenID: String?

    let screenIndex: Int
    let timestamp: Date

    init(appName: String, windowTitle: String, frame: CGRect, screenIndex: Int, relativeFrame: CGRect? = nil, screenID: String? = nil) {
        self.id = UUID()
        self.appName = appName
        self.windowTitle = windowTitle
        self.frame = frame
        self.screenIndex = screenIndex
        self.relativeFrame = relativeFrame
        self.screenID = screenID
        self.timestamp = Date()
    }
}
