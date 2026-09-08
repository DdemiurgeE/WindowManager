//
//  RestoreEvent.swift
//  WindowManager
//

import Foundation

struct RestoreEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let layoutName: String
    let screenConfiguration: ScreenConfiguration?
    let status: RestoreStatus
    let windowsTotal: Int
    let windowsRestored: Int

    enum RestoreStatus: String, Codable {
        case started
        case completed
        case cancelled
        case noMatch
        case skipped
    }

    init(
        layoutName: String,
        screenConfiguration: ScreenConfiguration?,
        status: RestoreStatus,
        windowsTotal: Int,
        windowsRestored: Int = 0
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.layoutName = layoutName
        self.screenConfiguration = screenConfiguration
        self.status = status
        self.windowsTotal = windowsTotal
        self.windowsRestored = windowsRestored
    }
}
