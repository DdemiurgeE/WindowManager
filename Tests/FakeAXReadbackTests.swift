import Foundation
import CoreGraphics

final class FakeAX {
    var position = CGPoint.zero
    var size = CGSize.zero
    var clampSize: CGSize?
    var driftAfterSize = false
    var failPositionSet = false
    var failSizeSet = false
    var failPositionGet = false
    var failSizeGet = false
    var failRetryPositionSet = false
    var failReadAfterFirst = false
    var positionSets = 0
    var sizeSets = 0
    var reads = 0

    func setPosition(_ value: CGPoint) -> Result<Void, FrameRestoreError> {
        positionSets += 1
        if failRetryPositionSet && positionSets > 1 { return .failure(.message("retry position set")) }
        guard !failPositionSet else { return .failure(.message("position set")) }
        position = value
        return .success(())
    }

    func setSize(_ value: CGSize) -> Result<Void, FrameRestoreError> {
        sizeSets += 1
        guard !failSizeSet else { return .failure(.message("size set")) }
        size = clampSize ?? value
        if driftAfterSize { position.x += 40 }
        return .success(())
    }

    func read() -> Result<WindowFrameReadback, FrameRestoreError> {
        reads += 1
        if failReadAfterFirst && reads > 1 { return .failure(.message("final read")) }
        guard !failPositionGet else { return .failure(.message("position read")) }
        guard !failSizeGet else { return .failure(.message("size read")) }
        return .success(WindowFrameReadback(position: position, size: size))
    }
}

@inline(__always)
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FakeAXReadbackTests failed: \(message)") }
}

func run(_ ax: FakeAX, position: CGPoint, size: CGSize, shouldContinue: @escaping () -> Bool = { true }) -> FrameRestoreStatus {
    FrameRestoreEngine().restore(
        position: position,
        size: size,
        setPosition: ax.setPosition,
        setSize: ax.setSize,
        read: ax.read,
        shouldContinue: shouldContinue
    )
}

@main struct FakeAXReadbackTests {
    static func main() {
        var tests = 0

        let exact = FakeAX()
        check(run(exact, position: CGPoint(x: 10, y: 20), size: CGSize(width: 800, height: 600)) == .exact, "exact restore")
        check(exact.positionSets == 1 && exact.sizeSets == 1 && exact.reads == 1, "exact operation counts")
        tests += 2

        let clamped = FakeAX()
        clamped.clampSize = CGSize(width: 640, height: 480)
        check(run(clamped, position: .zero, size: CGSize(width: 800, height: 600)) == .appImposedClamp, "size clamp")
        check(clamped.positionSets == 1 && clamped.reads == 1, "size clamp does not retry")
        tests += 2

        let drift = FakeAX()
        drift.driftAfterSize = true
        check(run(drift, position: .zero, size: CGSize(width: 800, height: 600)) == .exact, "position drift recovery")
        check(drift.positionSets == 2 && drift.reads == 2, "one bounded retry")
        tests += 2

        let failedSet = FakeAX()
        failedSet.failPositionSet = true
        check(run(failedSet, position: .zero, size: CGSize(width: 800, height: 600)) == .axFailure, "position set AX error")
        tests += 1

        let failedSize = FakeAX()
        failedSize.failSizeSet = true
        check(run(failedSize, position: .zero, size: CGSize(width: 800, height: 600)) == .axFailure, "size set AX error")
        tests += 1

        let failedGet = FakeAX()
        failedGet.failSizeGet = true
        check(run(failedGet, position: .zero, size: CGSize(width: 800, height: 600)) == .axFailure, "size get AX error")
        tests += 1

        let failedPositionGet = FakeAX()
        failedPositionGet.failPositionGet = true
        check(run(failedPositionGet, position: .zero, size: CGSize(width: 800, height: 600)) == .axFailure, "position get AX error")
        tests += 1

        let failedRetry = FakeAX()
        failedRetry.driftAfterSize = true
        failedRetry.failRetryPositionSet = true
        check(run(failedRetry, position: .zero, size: CGSize(width: 800, height: 600)) == .axFailure, "retry set AX error")
        check(failedRetry.positionSets == 2, "retry failure is bounded")
        tests += 2

        let failedFinalRead = FakeAX()
        failedFinalRead.driftAfterSize = true
        failedFinalRead.failReadAfterFirst = true
        check(run(failedFinalRead, position: .zero, size: CGSize(width: 800, height: 600)) == .axFailure, "final read AX error")
        tests += 1

        var checks = 0
        let stale = FakeAX()
        let staleResult = run(stale, position: .zero, size: CGSize(width: 800, height: 600)) {
            checks += 1
            return checks < 3
        }
        check(staleResult == .superseded, "stale callback superseded")
        check(stale.positionSets == 1, "stale callback does not continue writes")
        tests += 2

        let timeout = FakeAX()
        check(run(timeout, position: .zero, size: CGSize(width: 800, height: 600)) { false } == .superseded, "timeout before AX")
        check(timeout.positionSets == 0 && timeout.sizeSets == 0 && timeout.reads == 0, "timeout has no AX side effects")
        tests += 2

        // Every restore path has one final, read-back-derived status.
        let statuses: [WindowRestoreResult.WindowRestoreStatus] = [
            .appNotFound, .windowSkipped, .positionSet, .appImposedClamp,
            .axFailure, .coordinateUnavailable, .restoreSuperseded
        ]
        let result = RestoreResult(layoutName: "fake", windowsResults: statuses.map {
            WindowRestoreResult(appName: "Fake", windowTitle: "Window", status: $0)
        })
        check(result.windowsTotal == statuses.count, "result total")
        check(result.windowsRestored == 1 && result.summaryDescription == "1/7 windows restored", "result summary")
        tests += 2

        let matchedResult = RestoreResult(layoutName: "fake", windowsResults: [
            WindowRestoreResult(appName: "Fake", windowTitle: "Window", status: .windowMatched)
        ])
        let clampedResult = RestoreResult(layoutName: "fake", windowsResults: [
            WindowRestoreResult(appName: "Fake", windowTitle: "Window", status: .appImposedClamp)
        ])
        check(matchedResult.windowsRestored == 0 && matchedResult.summaryDescription == "0/1 windows restored", "window match is not restored")
        check(clampedResult.windowsRestored == 0 && clampedResult.summaryDescription == "0/1 windows restored", "app clamp is not restored")
        tests += 2

        // Layout JSON written before relativeFrame/screenID existed remains readable.
        let currentWindow = WindowInfo(
            appName: "Fake", windowTitle: "Old",
            frame: CGRect(x: 10, y: 20, width: 800, height: 600), screenIndex: 0)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var oldWindowObject = try! JSONSerialization.jsonObject(
            with: encoder.encode(currentWindow)) as! [String: Any]
        oldWindowObject.removeValue(forKey: "relativeFrame")
        oldWindowObject.removeValue(forKey: "screenID")
        let oldWindowJSON = try! JSONSerialization.data(withJSONObject: oldWindowObject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let oldWindow = try! decoder.decode(WindowInfo.self, from: oldWindowJSON)
        check(oldWindow.relativeFrame == nil && oldWindow.screenID == nil, "legacy layout JSON")
        tests += 1

        print("FakeAXReadbackTests: \(tests) tests passed")
    }
}
