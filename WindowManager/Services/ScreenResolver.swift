import AppKit
import CoreGraphics
import CryptoKit
import Foundation

/// Physical identity when the display supplies a unique, nonzero hardware serial.
/// The digest avoids persisting the serial itself; it is not a secret or a
/// substitute for validating uniqueness among currently attached displays.
enum DisplayIdentity {
    static func stableID(vendor: UInt32, model: UInt32, serial: UInt32) -> String? {
        guard vendor != 0, model != 0, serial != 0, serial != UInt32.max else { return nil }
        let bytes = SHA256.hash(data: Data("\(vendor):\(model):\(serial)".utf8))
        return "display_" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func resolveIDs(candidates: [String?], observations: [String]) -> [String] {
        guard candidates.count == observations.count else { return observations }
        let counts = candidates.compactMap { $0 }.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return candidates.indices.map { index in
            guard let id = candidates[index], counts[id] == 1 else { return observations[index] }
            return id
        }
    }

    static func screenIDs(for screens: [NSScreen]) -> [String] {
        let numbers = screens.map { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber }
        let candidates = numbers.map { number -> String? in
            guard let number else { return nil }
            let id = number.uint32Value
            return stableID(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                serial: CGDisplaySerialNumber(id))
        }
        let observations = screens.indices.map { index -> String in
            if let number = numbers[index] { return "screen_\(number.uint32Value)" }
            let frame = screens[index].frame
            return "screen_\(Int(frame.width))x\(Int(frame.height))_\(Int(frame.minX))_\(Int(frame.minY))"
        }
        return resolveIDs(candidates: candidates, observations: observations)
    }
}

/// Platform-neutral display information used by `ScreenResolver`.
/// `screenID` is an observation key, not a claim of hardware identity.
struct DisplaySnapshot: Equatable {
    let screenID: String?
    let frame: CGRect
    let visibleFrame: CGRect
    let scale: CGFloat?
    let index: Int

    init(screenID: String?, frame: CGRect, visibleFrame: CGRect? = nil, scale: CGFloat? = nil, index: Int) {
        self.screenID = screenID
        self.frame = frame
        self.visibleFrame = visibleFrame ?? frame
        self.scale = scale
        self.index = index
    }
}

/// The persisted information needed to restore one window without AppKit/AX.
struct WindowSnapshot: Equatable {
    let frame: CGRect
    let relativeFrame: CGRect?
    let screenID: String?
    let screenIndex: Int
    let savedDisplayFrame: CGRect?
    let savedVisibleFrame: CGRect?
    let preservePresentation: Bool
    let savedScale: CGFloat?

    init(
        frame: CGRect,
        relativeFrame: CGRect? = nil,
        screenID: String? = nil,
        screenIndex: Int,
        savedDisplayFrame: CGRect? = nil,
        savedVisibleFrame: CGRect? = nil,
        preservePresentation: Bool = false,
        savedScale: CGFloat? = nil
    ) {
        self.frame = frame
        self.relativeFrame = relativeFrame
        self.screenID = screenID
        self.screenIndex = screenIndex
        self.savedDisplayFrame = savedDisplayFrame
        self.savedVisibleFrame = savedVisibleFrame
        self.preservePresentation = preservePresentation
        self.savedScale = savedScale
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

/// Selects a display and restores a frame in points.
///
/// An unchanged display geometry gets the captured absolute frame exactly. When
/// the display or its available area changed, the normalized frame is used and
/// the result is kept reachable in the current visibleFrame. Presentation
/// states (fullscreen/maximized) opt out of shrinking/clamping.
struct ScreenResolver {
    let minimumUsefulTitleBar: CGFloat

    init(minimumUsefulTitleBar: CGFloat = 24) {
        self.minimumUsefulTitleBar = minimumUsefulTitleBar
    }

    func resolve(window: WindowSnapshot, displays: [DisplaySnapshot]) -> ResolvedWindowTarget? {
        guard !displays.isEmpty else { return nil }

        let selected: (display: DisplaySnapshot, selection: DisplaySelection)
        if let id = usableID(window.screenID), id.hasPrefix("display_") {
            // A missing or duplicated physical identity must not silently
            // redirect a window to a different external monitor.
            guard let display = uniqueDisplay(withID: id, in: displays) else { return nil }
            selected = (display, .screenID)
        } else if let id = usableID(window.screenID), !id.hasPrefix("screen_"),
           let display = uniqueDisplay(withID: id, in: displays) {
            selected = (display, .screenID)
        } else if let display = displayContainingWindowCenter(window.frame, displays: displays) {
            selected = (display, .frameCenter)
        } else if let display = display(at: window.screenIndex, in: displays) {
            selected = (display, .legacyScreenIndex)
        } else {
            selected = (displays.sorted(by: displayOrder).first!, .firstDisplay)
        }

        let sameGeometry: Bool
        if let savedDisplayFrame = window.savedDisplayFrame,
           let savedVisibleFrame = window.savedVisibleFrame,
           let savedScale = window.savedScale,
           let displayScale = selected.display.scale {
            sameGeometry = savedDisplayFrame == selected.display.frame
                && savedVisibleFrame == selected.display.visibleFrame
                && savedScale == displayScale
        } else {
            // Exact restoration requires a complete observation. Optional fields
            // are intentionally treated as legacy/incomplete metadata, not as
            // wildcards that can authorize an absolute-frame restore.
            sameGeometry = false
        }
        let candidate: CGRect
        if sameGeometry {
            candidate = window.frame
        } else if let relativeFrame = window.relativeFrame, relativeFrame.isFinite {
            candidate = CGRect(
                x: selected.display.frame.minX + relativeFrame.minX * selected.display.frame.width,
                y: selected.display.frame.minY + relativeFrame.minY * selected.display.frame.height,
                width: relativeFrame.width * selected.display.frame.width,
                height: relativeFrame.height * selected.display.frame.height
            )
        } else {
            candidate = window.frame
        }

        let target = window.preservePresentation ? candidate : clamp(candidate, to: selected.display.visibleFrame)
        return ResolvedWindowTarget(display: selected.display, frame: target, selection: selected.selection)
    }

    private func clamp(_ frame: CGRect, to visible: CGRect) -> CGRect {
        guard visible.isFinite, !visible.isEmpty, frame.isFinite else { return frame }
        // Keep the saved size. Even an oversized window retains a reachable
        // title-bar strip instead of being silently resized by the resolver.
        let minX = visible.minX + minimumUsefulTitleBar - frame.width
        let maxX = visible.maxX - minimumUsefulTitleBar
        let minY = visible.minY
        let maxY = visible.maxY - minimumUsefulTitleBar
        return CGRect(
            x: Swift.min(Swift.max(frame.minX, minX), maxX),
            y: Swift.min(Swift.max(frame.minY, minY), maxY),
            width: frame.width,
            height: frame.height
        )
    }

    private func uniqueDisplay(withID id: String, in displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        let matches = displays.filter { usableID($0.screenID) == id }
        return matches.count == 1 ? matches[0] : nil
    }

    private func displayContainingWindowCenter(_ frame: CGRect, displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return displays.filter { $0.frame.contains(center) }.sorted(by: displayOrder).first
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
