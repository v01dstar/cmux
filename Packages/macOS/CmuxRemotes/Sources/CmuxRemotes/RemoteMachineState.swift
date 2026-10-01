/// Cloud machine state, deliberately independent of workspace connection readiness.
public enum RemoteMachineState: Equatable, Sendable {
    /// No recent provider observation is available.
    case unknown
    /// The provider has accepted a start but has not reported running.
    case starting
    /// Compute is running; the session may still be connecting or unavailable.
    case running
    /// The provider has accepted a stop but has not reported stopped.
    case stopping
    /// The machine is explicitly stopped and must not be woken by reconnect.
    case stopped
    /// The latest observation or lifecycle operation failed.
    case error

    /// Maps the provider's desired and observed state without treating every suspension as a stop.
    public init(status: InstacloudComputeStatus) {
        if status.isStopped { self = .stopped }
        else if status.isRunning { self = .running }
        else if status.desiredState == "stopped" { self = .stopping }
        else if status.desiredState == "running" { self = .starting }
        else { self = .unknown }
    }
}
