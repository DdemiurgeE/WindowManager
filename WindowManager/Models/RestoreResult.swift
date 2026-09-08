//
//  RestoreResult.swift
//  WindowManager
//

import Foundation

struct WindowRestoreResult: Codable, Identifiable {
    let id: UUID
    let appName: String
    let windowTitle: String
    let status: WindowRestoreStatus

    enum WindowRestoreStatus: String, Codable {
        /// App with matching name was not found running
        case appNotFound
        /// Window matched by title or fallback
        case windowMatched
        /// No matching window found in the app
        case windowSkipped
        /// AX position/size set successfully
        case positionSet
    }

    init(appName: String, windowTitle: String, status: WindowRestoreStatus) {
        self.id = UUID()
        self.appName = appName
        self.windowTitle = windowTitle
        self.status = status
    }
}

struct RestoreResult {
    let layoutName: String
    let windowsResults: [WindowRestoreResult]

    var windowsTotal: Int { windowsResults.count }
    var windowsRestored: Int {
        windowsResults.filter { $0.status == .windowMatched || $0.status == .positionSet }.count
    }
    var summaryDescription: String {
        "\(windowsRestored)/\(windowsTotal) windows restored"
    }
}
