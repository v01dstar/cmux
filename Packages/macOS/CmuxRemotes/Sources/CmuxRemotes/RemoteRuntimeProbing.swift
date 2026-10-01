/// Reads runtime facts through the provider's bounded one-shot command API.
public protocol RemoteRuntimeProbing: Sendable {
    /// Verifies immutable service identity and running state before issuing the read-only probe.
    /// - Parameter locator: The exact compute selected by the user.
    /// - Returns: Runtime and persistent-storage facts from inside that machine.
    /// - Throws: Provider, approval, stopped-machine, or incompatible-runtime failures.
    func inspectRuntime(_ locator: InstacloudLocator) async throws -> RemoteRuntimeInspection
}
