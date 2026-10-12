import Foundation
import CoreGraphics

enum FakeStatus: Equatable { case exact, clamped, axFailure }

final class FakeAX {
    var position = CGPoint.zero
    var size = CGSize.zero
    var clampSize: CGSize?
    var failPositionSet = false
    var failSizeGet = false
    var positionSets = 0
    func setPosition(_ value: CGPoint) -> Bool { positionSets += 1; guard !failPositionSet else { return false }; position = value; return true }
    func setSize(_ value: CGSize) -> Bool { guard !failPositionSet else { return false }; size = clampSize ?? value; return true }
    func read() -> (CGPoint, CGSize)? { guard !failSizeGet else { return nil }; return (position, size) }
}

func restore(_ ax: FakeAX, position: CGPoint, size: CGSize) -> FakeStatus {
    guard ax.setPosition(position), ax.setSize(size), let first = ax.read() else { return .axFailure }
    let exact = abs(first.0.x - position.x) <= 2 && abs(first.0.y - position.y) <= 2 && abs(first.1.width - size.width) <= 2 && abs(first.1.height - size.height) <= 2
    if exact { return .exact }
    guard ax.setPosition(position), let final = ax.read() else { return .axFailure }
    let finalExact = abs(final.0.x - position.x) <= 2 && abs(final.0.y - position.y) <= 2 && abs(final.1.width - size.width) <= 2 && abs(final.1.height - size.height) <= 2
    return finalExact ? .exact : .clamped
}

@main struct FakeAXReadbackTests {
    static func main() {
        let exact = FakeAX(); assert(restore(exact, position: CGPoint(x: 10, y: 20), size: CGSize(width: 800, height: 600)) == .exact)
        let clamped = FakeAX(); clamped.clampSize = CGSize(width: 640, height: 480); assert(restore(clamped, position: .zero, size: CGSize(width: 800, height: 600)) == .clamped); assert(clamped.positionSets == 2)
        let failedSet = FakeAX(); failedSet.failPositionSet = true; assert(restore(failedSet, position: .zero, size: CGSize(width: 800, height: 600)) == .axFailure)
        let failedGet = FakeAX(); failedGet.failSizeGet = true; assert(restore(failedGet, position: .zero, size: CGSize(width: 800, height: 600)) == .axFailure)
        print("FakeAXReadbackTests: 4 tests passed")
    }
}
