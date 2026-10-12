import Foundation

/// Injectable state machine for ScreenMonitorService's delayed auto-apply path.
/// It has no AppKit or notification side effects, so topology and toggle races can
/// be exercised without mutating live displays or windows.
struct AutoApplyRetryPolicy {
    static func nextStableReadings<Value: Equatable>(
        previous: Value,
        current: Value,
        readings: Int
    ) -> Int {
        current == previous ? readings + 1 : 1
    }

    static func stabilityTimedOut(elapsed: TimeInterval, maximum: TimeInterval) -> Bool {
        elapsed >= maximum
    }

    enum RetryDecision: Equatable {
        case retry(number: Int)
        case finish
    }

    let maxRetries: Int
    private(set) var generation = 0
    private(set) var retryCount = 0
    private(set) var notificationPending = false
    private(set) var autoApplyEnabled = true

    init(maxRetries: Int = 3) {
        self.maxRetries = maxRetries
    }

    mutating func beginAttempt(autoApplyEnabled: Bool) {
        generation += 1
        retryCount = 0
        notificationPending = true
        self.autoApplyEnabled = autoApplyEnabled
    }

    mutating func cancelForTopology() {
        generation += 1
        retryCount = 0
        notificationPending = false
    }

    mutating func setAutoApplyEnabled(_ enabled: Bool) {
        autoApplyEnabled = enabled
    }

    func acceptsCallback(generation callbackGeneration: Int) -> Bool {
        callbackGeneration == generation
    }

    mutating func retryDecision(
        generation callbackGeneration: Int,
        missingWindows: Bool,
        autoApplyEnabled: Bool
    ) -> RetryDecision {
        self.autoApplyEnabled = autoApplyEnabled
        guard acceptsCallback(generation: callbackGeneration), autoApplyEnabled, missingWindows else {
            return .finish
        }
        guard retryCount < maxRetries else { return .finish }
        retryCount += 1
        return .retry(number: retryCount)
    }

    mutating func finishNotification(
        generation callbackGeneration: Int,
        autoApplyEnabled: Bool
    ) -> Bool {
        self.autoApplyEnabled = autoApplyEnabled
        guard acceptsCallback(generation: callbackGeneration), notificationPending else { return false }
        notificationPending = false
        return true
    }
}
