import Foundation

@inline(__always)
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("AutoApplyRetryPolicyTests failed: \(message)") }
}

@main
struct AutoApplyRetryPolicyTests {
    static func main() {
        var checks = 0
        var policy = AutoApplyRetryPolicy(maxRetries: 3)

        // Event storm: a new topology invalidates pending work and its callback.
        policy.beginAttempt(autoApplyEnabled: true)
        let staleGeneration = policy.generation
        require(policy.retryDecision(generation: staleGeneration, missingWindows: true, autoApplyEnabled: true) == .retry(number: 1), "first retry")
        policy.cancelForTopology()
        require(!policy.acceptsCallback(generation: staleGeneration), "stale retry rejected after topology event")
        require(policy.retryDecision(generation: staleGeneration, missingWindows: true, autoApplyEnabled: true) == .finish, "stale retry cannot schedule")
        require(!policy.finishNotification(generation: staleGeneration, autoApplyEnabled: true), "cancelled attempt cannot notify")
        checks += 4

        // Stable screen ID with changed geometry is not stable; identical geometry is.
        let old = "screen_1|0,0,1920,1080|2x"
        let resized = "screen_1|0,0,2560,1440|2x"
        require(AutoApplyRetryPolicy.nextStableReadings(previous: old, current: resized, readings: 2) == 1, "geometry change resets stability")
        require(AutoApplyRetryPolicy.nextStableReadings(previous: old, current: old, readings: 2) == 3, "unchanged topology advances stability")
        require(AutoApplyRetryPolicy.stabilityTimedOut(elapsed: 10, maximum: 10), "stability timeout")
        require(!AutoApplyRetryPolicy.stabilityTimedOut(elapsed: 9.99, maximum: 10), "pre-timeout remains pending")
        checks += 4

        // Toggle off during stability wait and immediately before retry both stop writes.
        policy.beginAttempt(autoApplyEnabled: true)
        let disabledGeneration = policy.generation
        policy.setAutoApplyEnabled(false)
        require(policy.retryDecision(generation: disabledGeneration, missingWindows: true, autoApplyEnabled: false) == .finish, "toggle off before retry")
        require(policy.finishNotification(generation: disabledGeneration, autoApplyEnabled: false), "disabled attempt still reaches one final notification")
        require(!policy.finishNotification(generation: disabledGeneration, autoApplyEnabled: false), "notification emitted once")
        checks += 3

        // Final notification is deferred through every bounded retry outcome.
        policy.beginAttempt(autoApplyEnabled: true)
        let retryGeneration = policy.generation
        require(policy.retryDecision(generation: retryGeneration, missingWindows: true, autoApplyEnabled: true) == .retry(number: 1), "retry 1")
        require(policy.retryDecision(generation: retryGeneration, missingWindows: true, autoApplyEnabled: true) == .retry(number: 2), "retry 2")
        require(policy.retryDecision(generation: retryGeneration, missingWindows: true, autoApplyEnabled: true) == .retry(number: 3), "retry 3")
        require(policy.retryDecision(generation: retryGeneration, missingWindows: true, autoApplyEnabled: true) == .finish, "bounded retry outcome")
        require(policy.notificationPending, "notification remains pending until bounded outcome")
        require(policy.finishNotification(generation: retryGeneration, autoApplyEnabled: true), "final notification")
        checks += 6

        print("AutoApplyRetryPolicyTests: \(checks) checks passed")
    }
}
