/// Desired and observed provider state; compute readiness is separate from session readiness.
public struct InstacloudComputeStatus: Decodable, Equatable, Sendable {
    /// Desired lifecycle state requested by the provider.
    public let desiredState: String
    /// Observed runtime state, including transient and suspended states.
    public let state: String

    /// True only when a machine has reached the provider's running state.
    public var isRunning: Bool { state == "running" }
    /// A suspension counts as an explicit stop only when stopped is also the desired state.
    public var isStopped: Bool {
        desiredState == "stopped" && (state == "suspended" || state == "stopped" || state == "none")
    }
}
