import Foundation
import CoreGraphics

/// A platform-neutral description of a window. AXUIElement values must be
/// converted to this value before calling WindowAssignment.
struct WindowAssignmentSnapshot: Equatable {
    let id: String
    let bundleID: String?
    let appName: String
    let title: String
    let role: String?
    let subrole: String?
    let frame: CGRect

    init(id: String, bundleID: String? = nil, appName: String,
         title: String = "", role: String? = nil, subrole: String? = nil,
         frame: CGRect = .zero) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.role = role
        self.subrole = subrole
        self.frame = frame
    }
}

enum WindowAssignmentStatus: Equatable {
    case matched(currentID: String)
    case ambiguous(candidateIDs: [String])
    case skipped(reason: WindowAssignmentSkipReason)
}

enum WindowAssignmentSkipReason: Equatable {
    case noIdentityMatch
    case noCompatibleWindow
    case alreadyAssigned
}

struct WindowAssignment: Equatable {
    let targetID: String
    let status: WindowAssignmentStatus
}

/// Deterministically assigns saved target snapshots to current snapshots.
///
/// The matcher deliberately does not use fuzzy string similarity. A changed
/// title may match only when app identity and accessibility role information
/// agree and geometry selects exactly one candidate. Ties are reported as
/// ambiguous so callers can leave the real windows untouched.
struct WindowAssigner {
    func assign(targets: [WindowAssignmentSnapshot], current: [WindowAssignmentSnapshot]) -> [WindowAssignment] {
        var used = Set<String>()
        var results: [WindowAssignment] = []

        for target in targets {
            let available = current.filter { !used.contains($0.id) }
            let identityMatches = available.filter { sameIdentity(target, $0) }
            guard !identityMatches.isEmpty else {
                results.append(WindowAssignment(targetID: target.id,
                                                status: .skipped(reason: .noIdentityMatch)))
                continue
            }

            let compatible = identityMatches.filter { compatibleRole(target, $0) }
            guard !compatible.isEmpty else {
                results.append(WindowAssignment(targetID: target.id,
                                                status: .skipped(reason: .noCompatibleWindow)))
                continue
            }

            let exactTitle = compatible.filter { !target.title.isEmpty && $0.title == target.title }
            let pool = exactTitle.isEmpty ? compatible : exactTitle
            let ranked = pool.sorted { lhs, rhs in
                let left = geometryDistance(target.frame, lhs.frame)
                let right = geometryDistance(target.frame, rhs.frame)
                if left != right { return left < right }
                return lhs.id < rhs.id
            }

            guard let best = ranked.first else {
                results.append(WindowAssignment(targetID: target.id,
                                                status: .skipped(reason: .noCompatibleWindow)))
                continue
            }
            let bestDistance = geometryDistance(target.frame, best.frame)
            let tied = ranked.filter { geometryDistance(target.frame, $0.frame) == bestDistance }
            if tied.count != 1 {
                results.append(WindowAssignment(
                    targetID: target.id,
                    status: .ambiguous(candidateIDs: tied.map(\.id).sorted())))
                continue
            }

            used.insert(best.id)
            results.append(WindowAssignment(targetID: target.id,
                                            status: .matched(currentID: best.id)))
        }
        return results
    }

    private func sameIdentity(_ target: WindowAssignmentSnapshot, _ current: WindowAssignmentSnapshot) -> Bool {
        if let targetBundle = nonEmpty(target.bundleID),
           let currentBundle = nonEmpty(current.bundleID) {
            return targetBundle == currentBundle
        }
        // Layouts created before bundle IDs were captured use the app name.
        return target.bundleID == nil && current.bundleID == nil &&
            !target.appName.isEmpty && target.appName == current.appName
    }

    private func compatibleRole(_ target: WindowAssignmentSnapshot, _ current: WindowAssignmentSnapshot) -> Bool {
        if let role = nonEmpty(target.role), role != current.role { return false }
        if let subrole = nonEmpty(target.subrole), subrole != current.subrole { return false }
        return true
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func geometryDistance(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let dx = Double(lhs.midX - rhs.midX)
        let dy = Double(lhs.midY - rhs.midY)
        let dw = Double(lhs.width - rhs.width)
        let dh = Double(lhs.height - rhs.height)
        return dx * dx + dy * dy + dw * dw + dh * dh
    }
}
