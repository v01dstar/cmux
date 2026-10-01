import Foundation

/// An immutable prepared runtime deployment directory and its verified content digest.
public struct RemoteRuntimeBundle: Equatable, Sendable {
    /// Private directory containing the deployment files, never credentials.
    public let directory: URL
    /// Digest covering the exact runtime inputs reserved by an operation.
    public let digest: String
    /// Creates the descriptor returned by a runtime preparation service.
    public init(directory: URL, digest: String) { self.directory = directory; self.digest = digest }
}
