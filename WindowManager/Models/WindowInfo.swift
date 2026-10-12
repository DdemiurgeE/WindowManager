//
//  WindowInfo.swift
//  WindowManager
//

import Foundation
import CoreGraphics

struct WindowInfo: Codable, Identifiable {
    let id: UUID
    let appName: String
    let bundleIdentifier: String?
    let windowTitle: String
    let axRole: String?
    let axSubrole: String?

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

    init(appName: String, windowTitle: String, frame: CGRect, screenIndex: Int, relativeFrame: CGRect? = nil, screenID: String? = nil, bundleIdentifier: String? = nil, axRole: String? = nil, axSubrole: String? = nil) {
        self.id = UUID()
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.axRole = axRole
        self.axSubrole = axSubrole
        self.frame = frame
        self.screenIndex = screenIndex
        self.relativeFrame = relativeFrame
        self.screenID = screenID
        self.timestamp = Date()
    }

    private enum CodingKeys: String, CodingKey {
        case id, appName, bundleIdentifier, windowTitle, axRole, axSubrole, frame, relativeFrame, screenID, screenIndex, timestamp
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        appName = try values.decode(String.self, forKey: .appName)
        bundleIdentifier = try values.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        windowTitle = try values.decode(String.self, forKey: .windowTitle)
        axRole = try values.decodeIfPresent(String.self, forKey: .axRole)
        axSubrole = try values.decodeIfPresent(String.self, forKey: .axSubrole)
        frame = try values.decode(CGRect.self, forKey: .frame)
        relativeFrame = try values.decodeIfPresent(CGRect.self, forKey: .relativeFrame)
        screenID = try values.decodeIfPresent(String.self, forKey: .screenID)
        screenIndex = try values.decode(Int.self, forKey: .screenIndex)
        timestamp = try values.decode(Date.self, forKey: .timestamp)
    }
}
