/// Persists atomic changes and publishes complete remote inventory snapshots.
public protocol RemoteConfigurationStoring: Sendable {
    /// Loads and validates the current configuration.
    func load() async throws -> RemoteConfiguration
    /// Commits one change atomically and returns the persisted snapshot.
    func apply(_ change: RemoteConfigurationChange) async throws -> RemoteConfiguration
    /// Publishes the initial snapshot followed by each successful commit.
    func updates() async throws -> AsyncStream<RemoteConfiguration>
}
