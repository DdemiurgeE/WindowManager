import CoreGraphics
import Foundation

/// Platform-neutral display information used by `ScreenResolver`.
/// `screenID` is an observation key, not a claim of hardware identity.
struct DisplaySnapshot: Equatable {
    let screenID: String?
    let frame: CGRect
    let index: Int

    init(screenID: String?, frame: CGRect, index: Int) {
        self.screenID = screenID
        self.frame = frame
        self.index = index
    }
}

/// The persisted information needed to restore one window without AppKit/AX.
struct WindowSnapshot: Equatable {
    let frame: CGRect
    let relativeFrame: CGRect?
    let screenID: String?
    let screenIndex: Int

    init(frame: CGRect, relativeFrame: CGRect? = nil, screenID: String? = nil, screenIndex: Int) {
        self.frame = frame
        self.relativeFrame = relativeFrame
        self.screenID = screenID
        self.screenIndex = screenIndex
    }
}

enum DisplaySelection: Equatable {
    case screenID
    case frameCenter
    case legacyScreenIndex
    case firstDisplay
}

struct ResolvedWindowTarget: Equatable {
    let display: DisplaySnapshot
    let frame: CGRect
    let selection: DisplaySelection
}

/// Selects a physical display first, then computes the target frame on it.
/// No AppKit, NSScreen, AX, or normalized-coordinate display matching is used.
struct ScreenResolver {
    func resolve(window: WindowSnapshot, displays: [DisplaySnapshot]) -> ResolvedWindowTarget? {
        guard !displays.isEmpty else { return nil }

        let selected: (display: DisplaySnapshot, selection: DisplaySelection)
        if let id = usableID(window.screenID), let display = uniqueDisplay(withID: id, in: displays) {
            selected = (display, .screenID)
        } else if let display = displayContainingWindowCenter(window.frame, displays: displays) {
            selected = (display, .frameCenter)
        } else if let display = display(at: window.screenIndex, in: displays) {
            selected = (display, .legacyScreenIndex)
        } else {
            selected = (displays.sorted(by: displayOrder).first!, .firstDisplay)
        }

        let targetFrame: CGRect
        if let relativeFrame = window.relativeFrame, relativeFrame.isFinite {
            targetFrame = CGRect(
                x: selected.display.frame.minX + relativeFrame.minX * selected.display.frame.width,
                y: selected.display.frame.minY + relativeFrame.minY * selected.display.frame.height,
                width: relativeFrame.width * selected.display.frame.width,
                height: relativeFrame.height * selected.display.frame.height
            )
        } else {
            targetFrame = window.frame
        }

        return ResolvedWindowTarget(display: selected.display, frame: targetFrame, selection: selected.selection)
    }

    private func uniqueDisplay(withID id: String, in displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        let matches = displays.filter { usableID($0.screenID) == id }
        return matches.count == 1 ? matches[0] : nil
    }

    private func displayContainingWindowCenter(_ frame: CGRect, displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return displays
            .filter { $0.frame.contains(center) }
            .sorted(by: displayOrder)
            .first
    }

    private func display(at index: Int, in displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        guard index >= 0 else { return nil }
        return displays.first { $0.index == index } ?? displays.sorted(by: displayOrder).dropFirst(index).first
    }

    private func usableID(_ id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        return id
    }

    private func displayOrder(_ lhs: DisplaySnapshot, _ rhs: DisplaySnapshot) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
        if lhs.frame.minX != rhs.frame.minX { return lhs.frame.minX < rhs.frame.minX }
        return false
    }
}

private extension CGRect {
    var isFinite: Bool {
        origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
    }
}
