import Foundation

/// The explicit destination used by New Workspace, independent of the selected workspace.
public enum RemoteLocation: Codable, Equatable, Sendable {
    /// Creates on the local Mac.
    case local
    /// Creates on a saved remote, identified independently of its display name.
    case remote(UUID)
}
