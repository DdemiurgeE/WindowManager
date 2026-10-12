import Foundation
import CoreGraphics

struct WindowFrameReadback: Equatable {
    let position: CGPoint
    let size: CGSize
}

enum FrameRestoreStatus: Equatable {
    case exact
    case appImposedClamp
    case axFailure
    case superseded
}

enum FrameRestoreError: Error, Equatable, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let value): return value }
    }
}

/// Shared, side-effect-free decision logic for an AX frame restore.
/// The caller owns the AX bridge; every operation is represented as a Result so
/// an AX error cannot be mistaken for a successful write or read-back.
struct FrameRestoreEngine {
    typealias Operation<Value> = Result<Value, FrameRestoreError>
    typealias SetValue = (CGPoint) -> Operation<Void>
    typealias SetSize = (CGSize) -> Operation<Void>
    typealias Read = () -> Operation<WindowFrameReadback>

    let tolerance: CGFloat

    init(tolerance: CGFloat = 2) {
        self.tolerance = tolerance
    }

    func restore(
        position: CGPoint,
        size: CGSize,
        setPosition: @escaping SetValue,
        setSize: @escaping SetSize,
        read: @escaping Read,
        shouldContinue: () -> Bool = { true },
        onError: (String) -> Void = { _ in }
    ) -> FrameRestoreStatus {
        guard shouldContinue() else { return .superseded }
        let initialPosition = setPosition(position)
        guard case .success = initialPosition else {
            if case .failure(let error) = initialPosition { onError(error.description) }
            return .axFailure
        }
        guard shouldContinue() else { return .superseded }
        let sizeResult = setSize(size)
        guard case .success = sizeResult else {
            if case .failure(let error) = sizeResult { onError(error.description) }
            return .axFailure
        }
        guard shouldContinue() else { return .superseded }
        let firstResult = read()
        guard case .success(let first) = firstResult else {
            if case .failure(let error) = firstResult { onError(error.description) }
            return .axFailure
        }

        if matches(first, position: position, size: size) { return .exact }
        // A single retry is allowed only when the position drifted. Size-only
        // differences are an application clamp and must not cause a loop.
        guard !matchesPosition(first.position, position: position) else {
            return .appImposedClamp
        }
        guard shouldContinue() else { return .superseded }
        let retryPosition = setPosition(position)
        guard case .success = retryPosition else {
            if case .failure(let error) = retryPosition { onError(error.description) }
            return .axFailure
        }
        guard shouldContinue() else { return .superseded }
        let finalResult = read()
        guard case .success(let final) = finalResult else {
            if case .failure(let error) = finalResult { onError(error.description) }
            return .axFailure
        }
        return matches(final, position: position, size: size) ? .exact : .appImposedClamp
    }

    private func matches(_ value: WindowFrameReadback, position: CGPoint, size: CGSize) -> Bool {
        matchesPosition(value.position, position: position) &&
            abs(value.size.width - size.width) <= tolerance &&
            abs(value.size.height - size.height) <= tolerance
    }

    private func matchesPosition(_ value: CGPoint, position: CGPoint) -> Bool {
        abs(value.x - position.x) <= tolerance && abs(value.y - position.y) <= tolerance
    }
}
