/// Verified runtime facts collected inside a running compute without exposing environment variables.
public struct RemoteRuntimeInspection: Decodable, Sendable {
    /// Runtime family identifying images managed by this integration.
    public let kind: String
    /// Content digest of the deployed runtime bundle.
    public let digest: String
    /// Whether /data is a separate mounted filesystem.
    public let mounted: Bool
    /// Resolved home directory, required to reside on persistent storage.
    public let home: String
    /// Resolved workspace directory, required to reside on persistent storage.
    public let workspace: String
    /// Whether boot completed and the persistent marker matches the image marker.
    public let ready: Bool
    /// Identity reported by the actual executable, not just the image label.
    public let binary: RemoteBinaryIdentity
}
