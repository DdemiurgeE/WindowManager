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
    let layoutID: UUID?
    let layoutName: String
    let windowsResults: [WindowRestoreResult]

    init(layoutID: UUID? = nil, layoutName: String, windowsResults: [WindowRestoreResult]) {
        self.layoutID = layoutID
        self.layoutName = layoutName
        self.windowsResults = windowsResults
    }

    var windowsTotal: Int { windowsResults.count }
    var windowsRestored: Int {
        windowsResults.filter { $0.status == .positionSet }.count
    }
    var summaryDescription: String {
        "\(windowsRestored)/\(windowsTotal) windows restored"
    }

    var skippedCount: Int {
        windowsResults.filter { $0.status == .appNotFound || $0.status == .windowSkipped }.count
    }

    var accessibilityFailureCount: Int {
        windowsResults.filter { $0.status == .axFailure }.count
    }

    var clampCount: Int {
        windowsResults.filter { $0.status == .appImposedClamp }.count
    }

    /// `lastUsed` records that an apply was attempted, never that it succeeded.
    static let lastUsedPolicyDescription = "Last attempted (not proof of a successful restore)"
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

    static func retryableIDs(in results: [WindowRestoreResult]) -> Set<UUID> {
        Set(results.compactMap { result in
            switch result.status {
            case .appNotFound, .windowSkipped, .axFailure: return result.id
            default: return nil
            }
        })
    }

    static func redactedDiagnostics(for result: RestoreResult, includeWindowDetails: Bool) -> String {
        var lines = [
            "Layout: \(result.layoutName)",
            "Restored: \(result.windowsRestored)/\(result.windowsTotal)",
            "Skipped or missing: \(result.skippedCount)",
            "Accessibility failures: \(result.accessibilityFailureCount)",
            "Application clamps: \(result.clampCount)"
        ]
        if includeWindowDetails {
            lines.append(contentsOf: result.windowsResults.map {
                "\($0.appName) — \($0.windowTitle): \($0.status.rawValue)"
            })
        }
        return lines.joined(separator: "\n")
    }

    static func merged(previous: RestoreResult, retry: RestoreResult) -> RestoreResult {
        var latest = Dictionary(uniqueKeysWithValues: previous.windowsResults.map { ($0.id, $0) })
        for item in retry.windowsResults { latest[item.id] = item }
        let previousIDs = Set(previous.windowsResults.map(\.id))
        let order = previous.windowsResults.map(\.id) + retry.windowsResults.map(\.id).filter { !previousIDs.contains($0) }
        return RestoreResult(layoutID: retry.layoutID ?? previous.layoutID,
            layoutName: retry.layoutName, windowsResults: order.compactMap { latest[$0] })
    }
}
