import Foundation

/// Injected schedule for provider lifecycle status sampling, bounded by an attempt count.
public struct RemoteStatusSchedule: Sendable {
    /// Maximum number of status samples after a single lifecycle mutation.
    public let attempts: Int
    /// Waits for the next scheduled sample; tests supply an immediate virtual tick.
    public let next: @Sendable () async throws -> Void

    /// Creates a bounded sampling schedule.
    /// - Parameters:
    ///   - attempts: Positive upper bound on provider observations.
    ///   - next: Cancellable scheduling seam; the production delay is the requested sampling interval.
    public init(attempts: Int = 60, next: @escaping @Sendable () async throws -> Void = {
        // Provider APIs expose status sampling rather than a push stream. This is the sampling cadence,
        // not a delay used to order tasks or wait for local state to settle.
        try await ContinuousClock().sleep(for: .seconds(2))
    }) {
        self.attempts = max(1, attempts)
        self.next = next
    }
}
