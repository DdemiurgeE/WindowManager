import Foundation

/// Maps a non-executable plan item to the same diagnostic used by restoreLayout.
enum RestorePlanResultMapping {
    static func result(forSkipped item: WindowRestorePlanItem) -> WindowRestoreResult {
        let status: WindowRestoreResult.WindowRestoreStatus
        switch item.skipReason {
        case .appNotFound: status = .appNotFound
        case .axFailure: status = .axFailure
        case .coordinateUnavailable: status = .coordinateUnavailable
        default: status = .windowSkipped
        }
        return WindowRestoreResult(id: item.windowID, appName: item.appName,
                                   windowTitle: item.windowTitle, status: status)
    }
}
