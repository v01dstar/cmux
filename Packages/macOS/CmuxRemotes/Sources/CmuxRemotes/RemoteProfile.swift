import Foundation

/// A saved machine connection, separate from both workspace state and cloud credentials.
public struct RemoteProfile: Codable, Equatable, Identifiable, Sendable {
    /// Stable local identity, preserved across reconnects and display-name changes.
    public let id: UUID
    /// User-visible machine label.
    public var name: String
    /// Provider identity and connection information.
    public var target: Target
    /// Persisted before stopping a machine so session restore cannot wake it again.
    public var automaticReconnectEnabled: Bool

    /// The supported connection kinds.
    public enum Target: Codable, Equatable, Sendable {
        /// An existing SSH host or host alias; advanced options remain in SSH configuration.
        case ssh(destination: String)
        /// A compute managed through the user's Instacloud CLI identity.
        case instacloud(InstacloudLocator)
    }

    /// Creates a saved connection with automatic reconnect initially enabled.
    public init(id: UUID = UUID(), name: String, target: Target, automaticReconnectEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.target = target
        self.automaticReconnectEnabled = automaticReconnectEnabled
    }
}
