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
        testSameGeometryPreservesExactPoints()
        testIncompleteGeometryMetadataUsesNormalizedFallback()
        testScaleChangeUsesNormalizedFallback()
        testResolutionChangeUsesSelectedDisplayForRelativeFrame()
        testVisibleFrameClampKeepsTitleBarAndSize()
        testPresentationStateIsNotShrunk()
        testMissingScreenIDUsesSavedAbsoluteFrameCenter()
        testDuplicateScreenIDFallsBackWithoutGuessingIdentity()
        testNegativeArrangementAndLegacyIndexFallback()
        testEmptyDisplaySetReturnsNil()
        testLegacyJSONWithoutOptionalGeometryStillDecodes()
        print("ScreenResolverTests: 12 tests passed")
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

    private static func testSameGeometryPreservesExactPoints() {
        let frame = CGRect(x: 137, y: 211, width: 777, height: 533)
        let displayFrame = CGRect(x: -1200, y: -300, width: 1920, height: 1080)
        let visible = CGRect(x: -1200, y: -270, width: 1920, height: 1040)
        let display = DisplaySnapshot(screenID: "left", frame: displayFrame, visibleFrame: visible, scale: 2, index: 0)
        let window = WindowSnapshot(frame: frame, relativeFrame: CGRect(x: 0, y: 0, width: 1, height: 1), screenID: "left", screenIndex: 0, savedDisplayFrame: displayFrame, savedVisibleFrame: visible, savedScale: 2)
        let result = ScreenResolver().resolve(window: window, displays: [display])
        assertEqual(result?.frame, frame, "same geometry exact point frame")
    }

    private static func testIncompleteGeometryMetadataUsesNormalizedFallback() {
        let displayFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let display = DisplaySnapshot(screenID: "primary", frame: displayFrame, visibleFrame: displayFrame, scale: 2, index: 0)
        let expectedRelativeFrame = CGRect(x: 0.7, y: 0.5, width: 0.2, height: 0.2)
        let exactFrame = CGRect(x: 10, y: 20, width: 100, height: 100)

        let complete = WindowSnapshot(frame: exactFrame, relativeFrame: expectedRelativeFrame, screenID: "primary", screenIndex: 0, savedDisplayFrame: displayFrame, savedVisibleFrame: displayFrame, savedScale: 2)
        assertEqual(ScreenResolver().resolve(window: complete, displays: [display])?.frame, exactFrame, "complete metadata exact frame")

        let missingDisplayFrame = WindowSnapshot(frame: exactFrame, relativeFrame: expectedRelativeFrame, screenID: "primary", screenIndex: 0, savedVisibleFrame: displayFrame, savedScale: 2)
        assertEqual(ScreenResolver().resolve(window: missingDisplayFrame, displays: [display])?.frame, CGRect(x: 700, y: 400, width: 200, height: 160), "missing display frame fallback")

        let missingVisibleFrame = WindowSnapshot(frame: exactFrame, relativeFrame: expectedRelativeFrame, screenID: "primary", screenIndex: 0, savedDisplayFrame: displayFrame, savedScale: 2)
        assertEqual(ScreenResolver().resolve(window: missingVisibleFrame, displays: [display])?.frame, CGRect(x: 700, y: 400, width: 200, height: 160), "missing visible frame fallback")

        let missingScale = WindowSnapshot(frame: exactFrame, relativeFrame: expectedRelativeFrame, screenID: "primary", screenIndex: 0, savedDisplayFrame: displayFrame, savedVisibleFrame: displayFrame)
        assertEqual(ScreenResolver().resolve(window: missingScale, displays: [display])?.frame, CGRect(x: 700, y: 400, width: 200, height: 160), "missing scale fallback")
    }

    private static func testScaleChangeUsesNormalizedFallback() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let displayFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let display = DisplaySnapshot(screenID: "primary", frame: displayFrame, visibleFrame: displayFrame, scale: 2, index: 0)
        let window = WindowSnapshot(frame: frame, relativeFrame: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), screenID: "primary", screenIndex: 0, savedDisplayFrame: displayFrame, savedVisibleFrame: displayFrame, savedScale: 1)
        let result = ScreenResolver().resolve(window: window, displays: [display])
        assertEqual(result?.frame, CGRect(x: 480, y: 270, width: 960, height: 540), "scale normalized fallback")
    }

    private static func testVisibleFrameClampKeepsTitleBarAndSize() {
        let visible = CGRect(x: 0, y: 22, width: 1200, height: 778)
        let display = DisplaySnapshot(screenID: "primary", frame: CGRect(x: 0, y: 0, width: 1200, height: 800), visibleFrame: visible, index: 0)
        let window = WindowSnapshot(frame: CGRect(x: -800, y: -500, width: 1400, height: 900), screenID: "primary", screenIndex: 0)
        let result = ScreenResolver().resolve(window: window, displays: [display])
        assertEqual(result?.frame, CGRect(x: -800, y: 22, width: 1400, height: 900), "visible frame clamp")
    }

    private static func testPresentationStateIsNotShrunk() {
        let display = DisplaySnapshot(screenID: "primary", frame: CGRect(x: 0, y: 0, width: 1200, height: 800), visibleFrame: CGRect(x: 0, y: 22, width: 1200, height: 778), index: 0)
        let frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let window = WindowSnapshot(frame: frame, relativeFrame: CGRect(x: 0, y: 0, width: 1, height: 1), screenID: "primary", screenIndex: 0, preservePresentation: true)
        let result = ScreenResolver().resolve(window: window, displays: [display])
        assertEqual(result?.frame, frame, "presentation frame preserved")
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
        assertEqual(result?.frame, CGRect(x: 1896, y: 1056, width: 100, height: 100), "absolute fallback frame")
    }

    private static func testEmptyDisplaySetReturnsNil() {
        let window = WindowSnapshot(frame: .zero, screenIndex: 0)
        assertNil(ScreenResolver().resolve(window: window, displays: []), "empty display set")
    }

    private static func testLegacyJSONWithoutOptionalGeometryStillDecodes() {
        let original = WindowInfo(appName: "Test", windowTitle: "Legacy", frame: CGRect(x: 10, y: 20, width: 300, height: 200), screenIndex: 0)
        let encoder = JSONEncoder()
        let data = try! encoder.encode(original)
        var object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "savedDisplayFrame")
        object.removeValue(forKey: "savedVisibleFrame")
        object.removeValue(forKey: "savedScale")
        let legacyData = try! JSONSerialization.data(withJSONObject: object)
        let decoded = try! JSONDecoder().decode(WindowInfo.self, from: legacyData)
        assertNil(decoded.savedDisplayFrame, "legacy display frame")
        assertNil(decoded.savedVisibleFrame, "legacy visible frame")
        assertNil(decoded.savedScale, "legacy scale")
    }
}
