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
        testTransientDisplayIDsDoNotSwapExternalMonitors()
        testPhysicalFingerprintSurvivesTransientIDSwap()
        testUnavailableOrDuplicateHardwareFingerprintFallsBackToObservation()
        testMissingPhysicalMonitorDoesNotMoveItsWindowsToAnother()
        testAutoApplyMatchesPhysicalTopologyWithoutTrustingTransientIDs()
        testNegativeArrangementAndLegacyIndexFallback()
        testEmptyDisplaySetReturnsNil()
        testLegacyJSONWithoutOptionalGeometryStillDecodes()
        print("ScreenResolverTests: 17 tests passed")
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

    private static func testTransientDisplayIDsDoNotSwapExternalMonitors() {
        let saved = WindowSnapshot(
            frame: CGRect(x: -1300, y: 150, width: 500, height: 350),
            relativeFrame: CGRect(x: 0.15, y: 0.15, width: 0.5, height: 0.4),
            screenID: "screen_21", screenIndex: 1)
        let leftAfterReconnect = DisplaySnapshot(screenID: "screen_42", frame: CGRect(x: -1600, y: 0, width: 1600, height: 900), index: 1)
        let rightAfterReconnect = DisplaySnapshot(screenID: "screen_21", frame: CGRect(x: 1920, y: 0, width: 1600, height: 900), index: 2)
        let result = ScreenResolver().resolve(window: saved, displays: [primary, leftAfterReconnect, rightAfterReconnect])
        assertEqual(result?.display, leftAfterReconnect, "transient ID must not override saved geometry")
        assertEqual(result?.selection, .frameCenter, "legacy ID uses saved geometry")
    }

    private static func testPhysicalFingerprintSurvivesTransientIDSwap() {
        let leftID = DisplayIdentity.stableID(vendor: 111, model: 22, serial: 333)
        let rightID = DisplayIdentity.stableID(vendor: 111, model: 22, serial: 444)
        precondition(leftID != nil && leftID != rightID, "two monitors must have distinct fingerprints")
        assertEqual(leftID, DisplayIdentity.stableID(vendor: 111, model: 22, serial: 333), "stable across reconnect")
        assertNil(DisplayIdentity.stableID(vendor: 111, model: 22, serial: 0), "unknown serial is not identity")
        assertNil(DisplayIdentity.stableID(vendor: 0, model: 22, serial: 333), "unknown vendor is not identity")

        let saved = WindowSnapshot(frame: CGRect(x: -1200, y: 200, width: 400, height: 300),
            relativeFrame: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.3), screenID: leftID, screenIndex: 1)
        let movedLeft = DisplaySnapshot(screenID: leftID, frame: CGRect(x: 1920, y: 0, width: 1600, height: 900), index: 2)
        let movedRight = DisplaySnapshot(screenID: rightID, frame: CGRect(x: -1600, y: 0, width: 1600, height: 900), index: 1)
        let result = ScreenResolver().resolve(window: saved, displays: [primary, movedRight, movedLeft])
        assertEqual(result?.display, movedLeft, "physical monitor selected after positions swap")
        assertEqual(result?.selection, .screenID, "physical fingerprint strategy")
    }

    private static func testUnavailableOrDuplicateHardwareFingerprintFallsBackToObservation() {
        let ids = DisplayIdentity.resolveIDs(candidates: ["display_same", "display_same", nil, "display_unique"],
            observations: ["screen_1", "screen_2", "screen_3", "screen_4"])
        assertEqual(ids, ["screen_1", "screen_2", "screen_3", "display_unique"], "ambiguous hardware identity does not masquerade as unique")
    }

    private static func testMissingPhysicalMonitorDoesNotMoveItsWindowsToAnother() {
        let missing = DisplayIdentity.stableID(vendor: 111, model: 22, serial: 333)!
        let other = DisplayIdentity.stableID(vendor: 111, model: 22, serial: 444)!
        let saved = WindowSnapshot(frame: CGRect(x: 100, y: 100, width: 300, height: 200),
            relativeFrame: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3), screenID: missing, screenIndex: 0)
        let remaining = DisplaySnapshot(screenID: other, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), index: 0)
        assertNil(ScreenResolver().resolve(window: saved, displays: [remaining]), "missing physical monitor should not receive another monitor's windows")
    }

    private static func testAutoApplyMatchesPhysicalTopologyWithoutTrustingTransientIDs() {
        let left = DisplayIdentity.stableID(vendor: 111, model: 22, serial: 333)!
        let right = DisplayIdentity.stableID(vendor: 111, model: 22, serial: 444)!
        func screen(_ id: String, _ x: CGFloat) -> ScreenConfiguration.Screen {
            let frame = CGRect(x: x, y: 0, width: 1600, height: 900)
            return .init(id: id, frame: frame, visibleFrame: frame, scale: 2)
        }
        let saved = ScreenConfiguration(screens: [screen(left, -1600), screen(right, 1920)])
        let swapped = ScreenConfiguration(screens: [screen(right, -1600), screen(left, 1920)])
        precondition(saved.matchesForAutoApply(swapped), "same physical pair after geometry swap")
        let unknown = ScreenConfiguration(screens: [screen("screen_21", -1600), screen("screen_42", 1920)])
        precondition(!unknown.matchesForAutoApply(unknown), "transient IDs cannot authorize auto-apply")
        let duplicate = ScreenConfiguration(screens: [screen(left, -1600), screen(left, 1920)])
        precondition(!duplicate.matchesForAutoApply(duplicate), "duplicate fingerprint cannot authorize auto-apply")
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
