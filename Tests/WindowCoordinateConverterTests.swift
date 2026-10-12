import Foundation

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    precondition(actual == expected, "\(message): got \(actual), expected \(expected)")
}

@main
struct WindowCoordinateConverterTests {
    static func main() {
        testDifferentHeightScreensUsePrimaryHeight()
        testNegativeXAndYArrangement()
        testPrimaryOriginIsIncludedInBothAxes()
        testRoundTripSurvivesMainFocusChange()
        print("WindowCoordinateConverterTests: 4 tests passed")
    }

    private static func testDifferentHeightScreensUsePrimaryHeight() {
        let converter = WindowCoordinateConverter(primaryScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        assertEqual(converter.axOriginToScreenFrame(axOrigin: CGPoint(x: 100, y: 100), size: CGSize(width: 800, height: 600)),
                    CGRect(x: 100, y: 380, width: 800, height: 600),
                    "different screen heights")
    }

    private static func testNegativeXAndYArrangement() {
        let converter = WindowCoordinateConverter(primaryScreenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440))
        let frame = CGRect(x: -1200, y: -300, width: 1000, height: 700)
        let ax = converter.screenFrameToAXOrigin(frame)
        assertEqual(ax, CGPoint(x: -1200, y: 1040), "negative X/Y arrangement")
        assertEqual(converter.axOriginToScreenFrame(axOrigin: ax, size: frame.size), frame, "negative arrangement round-trip")
    }

    private static func testPrimaryOriginIsIncludedInBothAxes() {
        let converter = WindowCoordinateConverter(primaryScreenFrame: CGRect(x: 300, y: 200, width: 1600, height: 900))
        let frame = CGRect(x: 450, y: 250, width: 500, height: 400)
        assertEqual(converter.axOriginToScreenFrame(axOrigin: CGPoint(x: 150, y: 450), size: frame.size), frame, "primary origin")
        assertEqual(converter.screenFrameToAXOrigin(frame), CGPoint(x: 150, y: 450), "primary origin reverse")
    }

    private static func testRoundTripSurvivesMainFocusChange() {
        let converter = WindowCoordinateConverter(primaryScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let frame = CGRect(x: 2200, y: 200, width: 1200, height: 800)
        let ax = converter.screenFrameToAXOrigin(frame)
        assertEqual(converter.axOriginToScreenFrame(axOrigin: ax, size: frame.size), frame, "focus-independent round-trip")
    }
}
