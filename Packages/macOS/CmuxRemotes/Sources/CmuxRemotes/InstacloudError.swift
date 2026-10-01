/// Safe structured provider failures; raw CLI output and credentials are never persisted.
public enum InstacloudError: Error, Equatable, Sendable {
    /// The CLI could not be launched.
    case unavailable
    /// Login must be completed in the user's browser.
    case loginRequired
    /// A command timed out; provisioning must reconcile before issuing another create.
    case timedOut
    /// The provider requires human approval for the original request.
    case approvalRequired(String?)
    /// A command failed without a recognized structured reason.
    case commandFailed(Int32?)
    /// The CLI output did not match the supported JSON contract.
    case invalidResponse
    /// A saved service name now points at a different immutable service ID.
    case identityChanged
    /// The saved compute no longer exists.
    case missingCompute
    /// An existing machine lacks the required persistent volume.
    case missingVolume
    /// The machine is transitioning or unavailable; workspace creation must not fall back locally.
    case machineNotRunning
    /// Lifecycle polling exhausted its deadline without reaching the requested state.
    case transitionTimedOut
    /// Creation found a conflicting name before any create request was issued.
    case nameConflict
    /// A create request was issued but inventory does not yet establish its outcome.
    case creationUncertain
    /// The runtime bundle differs from the one reserved by the provisioning operation.
    case bundleChanged
    /// The machine's runtime does not match the expected cmux runtime marker.
    case incompatibleRuntime
}
