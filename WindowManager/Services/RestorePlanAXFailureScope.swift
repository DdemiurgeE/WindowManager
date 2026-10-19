import Foundation

/// Keeps AX read failures local to unmatched targets, preserving valid planner matches.
struct RestorePlanAXFailureScope {
    static func idsToMark(plan: WindowRestorePlan, targetIDs: Set<UUID>) -> Set<UUID> {
        Set(plan.items.compactMap { item in
            guard item.candidateID == nil, targetIDs.contains(item.windowID) else { return nil }
            return item.windowID
        })
    }
}
