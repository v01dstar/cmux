import Foundation

/// Owns a private JSON configuration file; no credential material is stored here.
public actor RemoteConfigurationRepository: RemoteConfigurationStoring {
    private let fileURL: URL
    private let files: FileManager
    private var cached: RemoteConfiguration?
    private var observers: [UUID: AsyncStream<RemoteConfiguration>.Continuation] = [:]

    /// Creates a repository at an injected path; tests use temporary directories.
    public init(fileURL: URL, fileManager: FileManager) {
        self.fileURL = fileURL
        self.files = fileManager
    }

    /// Loads once, rejecting corrupt or unsupported data rather than discarding saved machines.
    public func load() throws -> RemoteConfiguration {
        if let cached { return cached }
        let configuration: RemoteConfiguration
        if files.fileExists(atPath: fileURL.path) {
            configuration = try JSONDecoder().decode(RemoteConfiguration.self, from: Data(contentsOf: fileURL))
            try configuration.validate()
        } else {
            configuration = RemoteConfiguration()
        }
        cached = configuration
        return configuration
    }

    /// Writes atomically before exposing a mutation to UI observers.
    public func apply(_ change: RemoteConfigurationChange) throws -> RemoteConfiguration {
        var next = try load()
        try next.apply(change)
        try files.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Background lifecycle and restore must read a closed file after the
        // user's first unlock, including while the screen is subsequently locked.
        try encoder.encode(next).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        cached = next
        for observer in observers.values { observer.yield(next) }
        return next
    }

    /// Streams durable snapshots; cancellation releases the observer.
    public func updates() throws -> AsyncStream<RemoteConfiguration> {
        let initial = try load()
        let id = UUID()
        let pair = AsyncStream<RemoteConfiguration>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = pair.continuation
        pair.continuation.yield(initial)
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return pair.stream
    }

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }
}
