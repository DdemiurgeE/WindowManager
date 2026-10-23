import AppKit
import Foundation

@main struct WindowSnapTests {
    static func main() {
        let frame = CGRect(x: -1600, y: 24, width: 1600, height: 876)
        func check(_ zone: SnapZone, _ expected: CGRect) {
            precondition(SnapGeometry.frame(for: zone, in: frame) == expected, "wrong frame for \(zone)")
        }
        check(.leftHalf, CGRect(x: -1600, y: 24, width: 800, height: 876))
        check(.rightHalf, CGRect(x: -800, y: 24, width: 800, height: 876))
        check(.topHalf, CGRect(x: -1600, y: 462, width: 1600, height: 438))
        check(.bottomHalf, CGRect(x: -1600, y: 24, width: 1600, height: 438))
        check(.topLeft, CGRect(x: -1600, y: 462, width: 800, height: 438))
        check(.bottomRight, CGRect(x: -800, y: 24, width: 800, height: 438))
        let third = CGFloat(1600) / 3
        check(.leftThird, CGRect(x: -1600, y: 24, width: third, height: 876))
        check(.middleThird, CGRect(x: -1600 + third, y: 24, width: third, height: 876))
        check(.rightTwoThirds, CGRect(x: -1600 + third, y: 24, width: 1600 - third, height: 876))
        check(.maximize, frame)
        let odd = CGRect(x: 25, y: -200, width: 1919, height: 1079)
        let left = SnapGeometry.frame(for: .leftHalf, in: odd)!
        let right = SnapGeometry.frame(for: .rightHalf, in: odd)!
        precondition(left.maxX == right.minX && right.maxX == odd.maxX,
            "odd-width halves must cover the display without gaps")
        let first = SnapGeometry.frame(for: .leftThird, in: odd)!
        let middle = SnapGeometry.frame(for: .middleThird, in: odd)!
        let last = SnapGeometry.frame(for: .rightThird, in: odd)!
        precondition(first.maxX == middle.minX && middle.maxX == last.minX && last.maxX == odd.maxX)
        precondition(SnapGeometry.frame(for: .maximize, in: .zero) == nil)

        let display = CGRect(x: -1600, y: 0, width: 1600, height: 900)
        precondition(SnapGeometry.edgeZone(at: CGPoint(x: -1598, y: 898), screen: display) == .topLeft)
        precondition(SnapGeometry.edgeZone(at: CGPoint(x: -2, y: 2), screen: display) == .bottomRight)
        precondition(SnapGeometry.edgeZone(at: CGPoint(x: -1598, y: 450), screen: display) == .leftHalf)
        precondition(SnapGeometry.edgeZone(at: CGPoint(x: -800, y: 898), screen: display) == .maximize)
        precondition(SnapGeometry.edgeZone(at: CGPoint(x: -1300, y: 2), screen: display) == .leftThird)
        precondition(SnapGeometry.edgeZone(at: CGPoint(x: -800, y: 2), screen: display) == .middleThird)
        precondition(SnapGeometry.edgeZone(at: CGPoint(x: -300, y: 2), screen: display) == .rightThird)
        precondition(SnapGeometry.edgeZone(at: CGPoint(x: -800, y: 450), screen: display) == nil)
        precondition(SnapGeometry.edgeZone(at: CGPoint(x: 5, y: 450), screen: display) == nil)
        precondition(SnapGeometry.edgeZone(at: CGPoint(x: -800, y: 450), screen: .zero) == nil)
        precondition(SnapGeometry.frame(for: .maximize, in: CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 100)) == nil)
        precondition(SnapGeometry.edgeZone(at: CGPoint(x: -1598, y: 898), screen: display, threshold: 0) == nil)
        let titleFrame = CGRect(x: 0, y: 100, width: 600, height: 400)
        precondition(SnapDragGesture.isTitleBarGrab(CGPoint(x: 300, y: 476), in: titleFrame))
        precondition(!SnapDragGesture.isTitleBarGrab(CGPoint(x: 300, y: 499), in: titleFrame),
            "top border resize is not a window drag")
        precondition(!SnapDragGesture.isTitleBarGrab(CGPoint(x: 300, y: 200), in: titleFrame))

        let a = SnapDisplay(id: "display_a", frame: display, visibleFrame: frame)
        let b = SnapDisplay(id: "display_b", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 24, width: 1920, height: 1056))
        precondition(SnapPlanner.target(zone: .rightHalf, displayID: "display_a", displays: [a, b]) ==
            CGRect(x: -800, y: 24, width: 800, height: 876))
        precondition(SnapPlanner.target(zone: .maximize, displayID: "display_missing", displays: [a, b]) == nil)
        precondition(SnapPlanner.target(zone: .maximize, displayID: "display_a", displays: [a, a]) == nil,
            "ambiguous target must not snap to another monitor")

        var drag = SnapDragGesture()
        drag.begin(at: CGPoint(x: 100, y: 100))
        precondition(!drag.observe(position: CGPoint(x: 104, y: 100)), "jitter does not activate snap")
        precondition(drag.observe(position: CGPoint(x: 112, y: 100)), "moved window can snap")
        drag.reset()
        precondition(!drag.isDraggingWindow, "release clears pending state")
        print("WindowSnapTests: geometry, edges, and drag gate passed")
    }
}
