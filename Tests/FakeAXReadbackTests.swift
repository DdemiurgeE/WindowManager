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
    var positionSets = 0

    func setPosition(_ value: CGPoint) -> Result<Void, FrameRestoreError> {
        positionSets += 1
        guard !failPositionSet else { return .failure(.message("position set")) }
        position = value
        return .success(())
    }

    func setSize(_ value: CGSize) -> Result<Void, FrameRestoreError> {
        guard !failSizeSet else { return .failure(.message("size set")) }
        size = clampSize ?? value
        if driftAfterSize { position.x += 40 }
        return .success(())
    }

    func read() -> Result<WindowFrameReadback, FrameRestoreError> {
        guard !failPositionGet else { return .failure(.message("position read")) }
        guard !failSizeGet else { return .failure(.message("size read")) }
        return .success(WindowFrameReadback(position: position, size: size))
    }
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
        let exact = FakeAX()
        assert(run(exact, position: CGPoint(x: 10, y: 20), size: CGSize(width: 800, height: 600)) == .exact)
        assert(exact.positionSets == 1)

        let clamped = FakeAX()
        clamped.clampSize = CGSize(width: 640, height: 480)
        assert(run(clamped, position: .zero, size: CGSize(width: 800, height: 600)) == .appImposedClamp)
        assert(clamped.positionSets == 1) // size-only clamp never retries

        let drift = FakeAX()
        drift.driftAfterSize = true
        assert(run(drift, position: .zero, size: CGSize(width: 800, height: 600)) == .exact)
        assert(drift.positionSets == 2) // exactly one bounded retry

        let failedSet = FakeAX()
        failedSet.failPositionSet = true
        assert(run(failedSet, position: .zero, size: CGSize(width: 800, height: 600)) == .axFailure)

        let failedSize = FakeAX()
        failedSize.failSizeSet = true
        assert(run(failedSize, position: .zero, size: CGSize(width: 800, height: 600)) == .axFailure)

        let failedGet = FakeAX()
        failedGet.failSizeGet = true
        assert(run(failedGet, position: .zero, size: CGSize(width: 800, height: 600)) == .axFailure)

        var checks = 0
        let stale = FakeAX()
        let staleResult = run(stale, position: .zero, size: CGSize(width: 800, height: 600)) {
            checks += 1
            return checks < 3
        }
        assert(staleResult == .superseded)
        assert(stale.positionSets == 1)

        let timeout = FakeAX()
        assert(run(timeout, position: .zero, size: CGSize(width: 800, height: 600)) { false } == .superseded)
        assert(timeout.positionSets == 0)

        print("FakeAXReadbackTests: 8 tests passed")
    }
}
