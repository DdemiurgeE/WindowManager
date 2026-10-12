import CoreGraphics
import Foundation

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    precondition(actual == expected, "\(message): got \(actual), expected \(expected)")
}

private func assertNil<T>(_ value: T?, _ message: String) {
    precondition(value == nil, "\(message): expected nil, got \(String(describing: value))")
}

@main
struct ScreenResolverTests {
    private static let left = DisplaySnapshot(screenID: "left", frame: CGRect(x: -1600, y: -200, width: 1600, height: 1200), index: 0)
    private static let primary = DisplaySnapshot(screenID: "primary", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), index: 1)

    static func main() {
        testScreenIDSelectsPhysicalDisplayBeforeFrameConversion()
        testResolutionChangeUsesSelectedDisplayForRelativeFrame()
        testMissingScreenIDUsesSavedAbsoluteFrameCenter()
        testDuplicateScreenIDFallsBackWithoutGuessingIdentity()
        testNegativeArrangementAndLegacyIndexFallback()
        testEmptyDisplaySetReturnsNil()
        print("ScreenResolverTests: 6 tests passed")
    }

    private static func testScreenIDSelectsPhysicalDisplayBeforeFrameConversion() {
        let window = WindowSnapshot(
            frame: CGRect(x: 100, y: 100, width: 400, height: 300),
            relativeFrame: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5),
            screenID: "left",
            screenIndex: 1
        )
        let result = ScreenResolver().resolve(window: window, displays: [primary, left])
        assertEqual(result?.display, left, "screen ID selection")
        assertEqual(result?.selection, .screenID, "screen ID strategy")
        assertEqual(result?.frame, CGRect(x: -1440, y: 40, width: 800, height: 600), "relative frame on selected display")
    }

    private static func testResolutionChangeUsesSelectedDisplayForRelativeFrame() {
        let resized = DisplaySnapshot(screenID: "primary", frame: CGRect(x: 300, y: -400, width: 2560, height: 1440), index: 0)
        let window = WindowSnapshot(
            frame: CGRect(x: 10, y: 10, width: 100, height: 100),
            relativeFrame: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25),
            screenID: "primary",
            screenIndex: 0
        )
        let result = ScreenResolver().resolve(window: window, displays: [resized])
        assertEqual(result?.frame, CGRect(x: 940, y: 320, width: 1280, height: 360), "resolution-independent relative frame")
    }

    private static func testMissingScreenIDUsesSavedAbsoluteFrameCenter() {
        let window = WindowSnapshot(frame: CGRect(x: -1200, y: 0, width: 400, height: 400), screenID: "disconnected", screenIndex: 1)
        let result = ScreenResolver().resolve(window: window, displays: [primary, left])
        assertEqual(result?.display, left, "absolute frame center fallback")
        assertEqual(result?.selection, .frameCenter, "frame center strategy")
        assertEqual(result?.frame, window.frame, "legacy absolute frame")
    }

    private static func testDuplicateScreenIDFallsBackWithoutGuessingIdentity() {
        let duplicateA = DisplaySnapshot(screenID: "reused", frame: CGRect(x: 0, y: 0, width: 1000, height: 800), index: 0)
        let duplicateB = DisplaySnapshot(screenID: "reused", frame: CGRect(x: 1000, y: 0, width: 1000, height: 800), index: 1)
        let window = WindowSnapshot(frame: CGRect(x: 1200, y: 100, width: 200, height: 200), relativeFrame: CGRect(x: 0, y: 0, width: 1, height: 1), screenID: "reused", screenIndex: 0)
        let result = ScreenResolver().resolve(window: window, displays: [duplicateA, duplicateB])
        assertEqual(result?.display, duplicateB, "duplicate ID geometry fallback")
        assertEqual(result?.selection, .frameCenter, "duplicate ID strategy")
    }

    private static func testNegativeArrangementAndLegacyIndexFallback() {
        let noIDs = [
            DisplaySnapshot(screenID: nil, frame: CGRect(x: -1920, y: -300, width: 1920, height: 1200), index: 4),
            DisplaySnapshot(screenID: nil, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), index: 9)
        ]
        let window = WindowSnapshot(frame: CGRect(x: 5000, y: 5000, width: 100, height: 100), relativeFrame: nil, screenID: nil, screenIndex: 9)
        let result = ScreenResolver().resolve(window: window, displays: noIDs)
        assertEqual(result?.display, noIDs[1], "legacy screen index")
        assertEqual(result?.selection, .legacyScreenIndex, "legacy index strategy")
        assertEqual(result?.frame, window.frame, "absolute fallback frame")
    }

    private static func testEmptyDisplaySetReturnsNil() {
        let window = WindowSnapshot(frame: .zero, screenIndex: 0)
        assertNil(ScreenResolver().resolve(window: window, displays: []), "empty display set")
    }
}
