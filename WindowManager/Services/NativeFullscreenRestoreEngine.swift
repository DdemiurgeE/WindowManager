import Foundation

/// Public AX attributes only. No Spaces identity/order is inferred.
enum NativeFullscreenFailure: Error { case unsupported, read, write }

/// Serial asynchronous transitions; the injected scheduler makes animation waits
/// deterministic in tests. Every continuation checks ownership before any AX work.
struct NativeFullscreenRestoreEngine {
    typealias Status = WindowRestoreResult.WindowRestoreStatus
    let pollLimit: Int
    init(pollLimit: Int = 32) { self.pollLimit = pollLimit }

    func restore(desired: Bool?,
                 read: @escaping () -> Result<Bool, NativeFullscreenFailure>,
                 capability: @escaping () -> Result<Bool, NativeFullscreenFailure>,
                 write: @escaping (Bool) -> Result<Void, NativeFullscreenFailure>,
                 onTargetDisplay: @escaping () -> Result<Bool, NativeFullscreenFailure>,
                 settled: @escaping () -> Result<Bool, NativeFullscreenFailure> = { .success(true) },
                 restoreFrame: @escaping () -> Status,
                 schedule: @escaping (@escaping () -> Void) -> Void,
                 shouldContinue: @escaping () -> Bool,
                 completion: @escaping (Status) -> Void) {
        func failure(_ error: NativeFullscreenFailure) -> Status {
            switch error {
            case .unsupported: return .fullscreenUnsupported
            case .read: return .fullscreenReadFailure
            case .write: return .fullscreenWriteFailure
            }
        }
        func active() -> Bool {
            guard shouldContinue() else { completion(.restoreSuperseded); return false }
            return true
        }
        func poll(_ expected: Bool, remaining: Int, matched: Bool = false, done: @escaping () -> Void) {
            guard active() else { return }
            switch read() {
            case .failure(let error): completion(failure(error))
            case .success(let state):
                // AXFullScreen may change before the animation finishes. Require
                // stable geometry as well as two matching scheduled state reads.
                let stable: Bool
                switch settled() {
                case .failure(let error): completion(failure(error)); return
                case .success(let value): stable = value
                }
                if state == expected && stable && matched { done(); return }
                guard remaining > 0 else { completion(.fullscreenTimeout); return }
                schedule { poll(expected, remaining: remaining - 1, matched: state == expected && stable, done: done) }
            }
        }
        func transition(_ state: Bool, done: @escaping () -> Void) {
            guard active() else { return }
            switch capability() {
            case .failure(let error): completion(failure(error)); return
            case .success(false): completion(.fullscreenUnsupported); return
            case .success(true): break
            }
            guard active() else { return }
            switch write(state) {
            case .failure(let error): completion(failure(error))
            case .success: schedule { poll(state, remaining: pollLimit, done: done) }
            }
        }
        func verifyDisplay(_ success: Status) {
            guard active() else { return }
            switch onTargetDisplay() {
            case .failure(let error): completion(failure(error))
            case .success(false): completion(.fullscreenDisplayMismatch)
            case .success(true): completion(success)
            }
        }
        func geometry() {
            guard active() else { return }
            let result = restoreFrame()
            guard result == .positionSet || result == .appImposedClamp else { completion(result); return }
            guard active() else { return }
            // A clamp onto a different monitor cannot be a fullscreen success.
            switch onTargetDisplay() {
            case .failure(let error): completion(failure(error))
            case .success(false): completion(.fullscreenDisplayMismatch)
            case .success(true):
                if desired == true { transition(true) { verifyDisplay(.positionSet) } }
                else { poll(false, remaining: pollLimit) { verifyDisplay(result) } }
            }
        }
        guard active() else { return }
        // Old/unreadable capture preserves historical geometry-only semantics.
        guard let desired else { completion(restoreFrame()); return }
        switch read() {
        case .failure(let error): completion(failure(error))
        case .success(let current):
            if current && desired {
                switch onTargetDisplay() {
                case .failure(let error): completion(failure(error))
                case .success(true): poll(true, remaining: pollLimit) { verifyDisplay(.positionSet) }
                case .success(false): transition(false, done: geometry)
                }
            } else if current { transition(false, done: geometry) }
            else { geometry() }
        }
    }
}
