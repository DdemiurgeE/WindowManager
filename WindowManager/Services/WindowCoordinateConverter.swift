import Foundation
import CoreGraphics

/// Converts between Accessibility/Quartz window origins and AppKit screen frames.
/// Both coordinate spaces are global; only the Y axis direction differs.
struct WindowCoordinateConverter {
    let primaryScreenFrame: CGRect

    func screenFrameToAXOrigin(_ frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.origin.x - primaryScreenFrame.origin.x,
            y: primaryScreenFrame.maxY - frame.maxY
        )
    }

    func axOriginToScreenFrame(axOrigin: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: primaryScreenFrame.minX + axOrigin.x,
            y: primaryScreenFrame.maxY - axOrigin.y - size.height,
            width: size.width,
            height: size.height
        )
    }
}