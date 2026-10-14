import Foundation
import CoreGraphics

/// Confidence attached to a restore decision. `none` means the window is skipped.
enum RestorePlanConfidence: String, Equatable {
    case high
    case medium
    case low
    case none
}

enum RestorePlanSkipReason: Equatable {
    case appNotFound
    case axFailure
    case noIdentityMatch
    case noCompatibleWindow
    case ambiguousCandidates
    case coordinateUnavailable
}

/// One side-effect-free restore decision for a saved window.
struct WindowRestorePlanItem: Equatable {
    let windowID: UUID
    let appName: String
    let windowTitle: String
    let chosenDisplay: DisplaySnapshot?
    let targetFrame: CGRect?
    let candidateID: String?
    let confidence: RestorePlanConfidence
    let reason: String
    let skipReason: RestorePlanSkipReason?

    var isSkipped: Bool { candidateID == nil || targetFrame == nil || skipReason != nil }
}

struct WindowRestorePlan: Equatable {
    let layoutName: String
    let items: [WindowRestorePlanItem]
}

/// Shared planning logic for preview and execution. It only consumes value
/// snapshots; callers are responsible for converting AX elements to snapshots.
struct RestorePlanner {
    func plan(layout: Layout,
              targets: [WindowInfo]? = nil,
              current: [WindowAssignmentSnapshot],
              displays: [DisplaySnapshot]) -> WindowRestorePlan {
        let selectedTargets = targets ?? layout.windows
        let assignments = WindowAssigner().assign(
            targets: selectedTargets.map { target in
                WindowAssignmentSnapshot(
                    id: target.id.uuidString,
                    bundleID: target.bundleIdentifier,
                    appName: target.appName,
                    title: target.windowTitle == "Untitled" ? "" : target.windowTitle,
                    role: target.axRole,
                    subrole: target.axSubrole,
                    frame: target.frame)
            },
            current: current)
        let displaysByIndex = displays.sorted { $0.index < $1.index }

        return WindowRestorePlan(layoutName: layout.name, items: selectedTargets.map { target in
            let assignment = assignments.first { $0.targetID == target.id.uuidString }?.status
            let targetFrame = resolve(target, displays: displaysByIndex)
            switch assignment ?? .skipped(reason: .noIdentityMatch) {
            case .matched(let currentID) where targetFrame != nil:
                let confidence: RestorePlanConfidence = target.windowTitle.isEmpty ? .medium : .high
                return WindowRestorePlanItem(windowID: target.id, appName: target.appName,
                    windowTitle: target.windowTitle, chosenDisplay: targetFrame?.display,
                    targetFrame: targetFrame?.frame, candidateID: currentID,
                    confidence: confidence, reason: "matched by deterministic identity and geometry",
                    skipReason: nil)
            case .matched where targetFrame == nil:
                return skipped(target, reason: "no usable display", skip: .coordinateUnavailable)
            case .ambiguous:
                return skipped(target, reason: "multiple equally suitable windows", skip: .ambiguousCandidates)
            case .skipped(.noIdentityMatch):
                return skipped(target, reason: "no matching application window", skip: .noIdentityMatch)
            case .skipped(.noCompatibleWindow), .skipped(.alreadyAssigned):
                return skipped(target, reason: "no compatible application window", skip: .noCompatibleWindow)
            default:
                return skipped(target, reason: "no compatible application window", skip: .noCompatibleWindow)
            }
        })
    }

    private func skipped(_ target: WindowInfo, reason: String, skip: RestorePlanSkipReason) -> WindowRestorePlanItem {
        WindowRestorePlanItem(windowID: target.id, appName: target.appName, windowTitle: target.windowTitle,
            chosenDisplay: nil, targetFrame: nil, candidateID: nil, confidence: .none,
            reason: reason, skipReason: skip)
    }

    private func resolve(_ target: WindowInfo, displays: [DisplaySnapshot]) -> ResolvedWindowTarget? {
        ScreenResolver().resolve(window: WindowSnapshot(
            frame: target.frame, relativeFrame: target.relativeFrame, screenID: target.screenID,
            screenIndex: target.screenIndex, savedDisplayFrame: target.savedDisplayFrame,
            savedVisibleFrame: target.savedVisibleFrame, preservePresentation: target.preservePresentation ?? false,
            savedScale: target.savedScale), displays: displays)
    }
}
