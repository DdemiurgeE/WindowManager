import AppKit
import Foundation

/// Target regions in a display's usable area (Dock/menu bar excluded).
enum SnapZone: String, CaseIterable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, middleThird, rightThird, leftTwoThirds, rightTwoThirds
    case maximize

    var id: String { rawValue }
    var title: String {
        switch self {
        case .leftHalf: "Left half"
        case .rightHalf: "Right half"
        case .topHalf: "Top half"
        case .bottomHalf: "Bottom half"
        case .topLeft: "Top left quarter"
        case .topRight: "Top right quarter"
        case .bottomLeft: "Bottom left quarter"
        case .bottomRight: "Bottom right quarter"
        case .leftThird: "Left third"
        case .middleThird: "Middle third"
        case .rightThird: "Right third"
        case .leftTwoThirds: "Left two thirds"
        case .rightTwoThirds: "Right two thirds"
        case .maximize: "Fill usable area"
        }
    }
}

enum SnapGeometry {
    static func frame(for zone: SnapZone, in visible: CGRect) -> CGRect? {
        guard visible.isFinite, visible.width > 0, visible.height > 0 else { return nil }
        let halfW = visible.width / 2, halfH = visible.height / 2, third = visible.width / 3
        let x = visible.minX, y = visible.minY
        switch zone {
        case .leftHalf: return CGRect(x: x, y: y, width: halfW, height: visible.height)
        case .rightHalf: return CGRect(x: x + halfW, y: y, width: visible.width - halfW, height: visible.height)
        case .topHalf: return CGRect(x: x, y: y + halfH, width: visible.width, height: visible.height - halfH)
        case .bottomHalf: return CGRect(x: x, y: y, width: visible.width, height: halfH)
        case .topLeft: return CGRect(x: x, y: y + halfH, width: halfW, height: visible.height - halfH)
        case .topRight: return CGRect(x: x + halfW, y: y + halfH, width: visible.width - halfW, height: visible.height - halfH)
        case .bottomLeft: return CGRect(x: x, y: y, width: halfW, height: halfH)
        case .bottomRight: return CGRect(x: x + halfW, y: y, width: visible.width - halfW, height: halfH)
        case .leftThird: return CGRect(x: x, y: y, width: third, height: visible.height)
        case .middleThird: return CGRect(x: x + third, y: y, width: third, height: visible.height)
        case .rightThird: return CGRect(x: x + 2 * third, y: y, width: visible.width - 2 * third, height: visible.height)
        case .leftTwoThirds: return CGRect(x: x, y: y, width: 2 * third, height: visible.height)
        case .rightTwoThirds: return CGRect(x: x + third, y: y, width: visible.width - third, height: visible.height)
        case .maximize: return visible
        }
    }

    /// Snap only at an actual display boundary, not along the edge of a
    /// window. Corners take precedence; bottom thirds follow pointer X.
    static func edgeZone(at point: CGPoint, screen: CGRect, threshold: CGFloat = 16) -> SnapZone? {
        guard screen.isFinite, screen.width > 0, screen.height > 0,
              threshold > 0, point.x >= screen.minX, point.x <= screen.maxX,
              point.y >= screen.minY, point.y <= screen.maxY else { return nil }
        let left = point.x - screen.minX <= threshold
        let right = screen.maxX - point.x <= threshold
        let bottom = point.y - screen.minY <= threshold
        let top = screen.maxY - point.y <= threshold
        if left && top { return .topLeft }
        if right && top { return .topRight }
        if left && bottom { return .bottomLeft }
        if right && bottom { return .bottomRight }
        if left { return .leftHalf }
        if right { return .rightHalf }
        if top { return .maximize }
        if bottom {
            let fraction = (point.x - screen.minX) / screen.width
            return fraction < 1 / 3 ? .leftThird : (fraction < 2 / 3 ? .middleThird : .rightThird)
        }
        return nil
    }
}

enum SnapActionResult {
    case positionSet, appImposedClamp, axFailure
    case permissionDenied, displayUnavailable, windowUnavailable, coordinateUnavailable

    var message: String {
        switch self {
        case .positionSet: "Window snapped."
        case .appImposedClamp: "The app adjusted the requested position or size."
        case .axFailure: "The app rejected the window change."
        case .permissionDenied: "Enable Accessibility permission to move windows."
        case .displayUnavailable: "The selected display changed. Refresh displays and retry."
        case .windowUnavailable: "The selected window changed or is unavailable. Refresh windows and retry."
        case .coordinateUnavailable: "Display coordinates are unavailable. No window was moved."
        }
    }
}

struct SnapDisplay {
    let id: String
    let frame: CGRect
    let visibleFrame: CGRect
}

enum SnapPlanner {
    static func target(zone: SnapZone, displayID: String, displays: [SnapDisplay]) -> CGRect? {
        let matches = displays.filter { $0.id == displayID }
        guard matches.count == 1 else { return nil }
        return SnapGeometry.frame(for: zone, in: matches[0].visibleFrame)
    }
}

/// A cursor near an edge is insufficient: the observed AX window must have
/// actually changed position during this mouse drag.
struct SnapDragGesture {
    static func isTitleBarGrab(_ point: CGPoint, in frame: CGRect) -> Bool {
        guard frame.isFinite, frame.contains(point) else { return false }
        let fromTop = frame.maxY - point.y
        return fromTop >= 8 && fromTop <= 48
    }

    private var initial: CGPoint?
    private(set) var isDraggingWindow = false

    mutating func begin(at position: CGPoint) {
        initial = position
        isDraggingWindow = false
    }

    @discardableResult mutating func observe(position: CGPoint) -> Bool {
        guard let initial else { return false }
        if hypot(position.x - initial.x, position.y - initial.y) >= 8 {
            isDraggingWindow = true
        }
        return isDraggingWindow
    }

    mutating func reset() {
        initial = nil
        isDraggingWindow = false
    }
}

private extension CGRect {
    var isFinite: Bool {
        minX.isFinite && minY.isFinite && width.isFinite && height.isFinite
    }
}
