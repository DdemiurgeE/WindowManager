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
        /// AX position/size were set and the read-back matches the target.
        case positionSet
        /// The application accepted the request but imposed a different frame.
        case appImposedClamp
        /// An Accessibility API operation failed.
        case axFailure
        /// The primary display was not available for coordinate conversion.
        case coordinateUnavailable
        /// A newer restore superseded this restore before its read-back finished.
        case restoreSuperseded
    }

    init(id: UUID = UUID(), appName: String, windowTitle: String, status: WindowRestoreStatus) {
        self.id = id
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
        windowsResults.filter { $0.status == .positionSet }.count
    }
    var summaryDescription: String {
        "\(windowsRestored)/\(windowsTotal) windows restored"
    }
}

enum RestoreResultMapping {
    static func statuses(for results: [WindowRestoreResult]) -> [UUID: WindowRestoreResult.WindowRestoreStatus] {
        Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0.status) })
    }

    static func retryableMissingIDs(
        in windows: [WindowInfo],
        results: [WindowRestoreResult]
    ) -> Set<UUID> {
        let statuses = statuses(for: results)
        return Set(windows.compactMap { window in
            guard let status = statuses[window.id] else { return window.id }
            return status == .appNotFound || status == .windowSkipped ? window.id : nil
        })
    }
}
