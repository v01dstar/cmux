/// Prepares versioned deployment inputs and checks the persistent runtime on an existing compute.
public protocol RemoteRuntimeServicing: Sendable {
    /// Returns an immutable bundle for the requested digest, or prepares the current bundle when nil.
    func bundle(digest: String?) async throws -> RemoteRuntimeBundle
    /// Recomputes the digest before deployment so changed files cannot be deployed under an old journal.
    func validate(_ bundle: RemoteRuntimeBundle) async throws
    /// Checks mounted storage and the runtime marker; nil permits compatible existing bundles.
    func verifyMachine(_ locator: InstacloudLocator, expectedDigest: String?) async throws
}
