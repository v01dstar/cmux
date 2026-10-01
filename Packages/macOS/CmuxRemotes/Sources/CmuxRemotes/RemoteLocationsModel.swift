import Foundation
import Observation

/// Shared settings/menu state and lifecycle orchestration for saved remote machines.
///
/// Construct once at app composition and inject into every entrypoint. UI disappearance does
/// not cancel accepted operations: the app owns their Tasks, and this model gates per machine.
@MainActor @Observable
public final class RemoteLocationsModel {
    /// Last durable configuration; delayed observations cannot replace newer revisions.
    public private(set) var configuration = RemoteConfiguration()
    /// Whether loading succeeded; workspace creation must wait instead of assuming Local.
    public private(set) var isLoaded = false
    /// Most recently observed machine states.
    public private(set) var states: [UUID: RemoteMachineState] = [:]
    /// Machines with an accepted lifecycle operation; other machines remain usable.
    public private(set) var busy: Set<UUID> = []
    /// Last failed operation, displayed by the caller using localized messages.
    public private(set) var lastError: (any Error)?

    private let repository: any RemoteConfigurationStoring
    private let provider: any InstacloudProviding
    private let schedule: RemoteStatusSchedule
    private let beforeStop: @MainActor (UUID) async -> Void

    /// Creates the domain model with injectable storage, provider, sampling, and workspace detach action.
    public init(repository: any RemoteConfigurationStoring, provider: any InstacloudProviding,
                schedule: RemoteStatusSchedule = RemoteStatusSchedule(),
                beforeStop: @escaping @MainActor (UUID) async -> Void = { _ in }) {
        self.repository = repository
        self.provider = provider
        self.schedule = schedule
        self.beforeStop = beforeStop
    }

    /// Loads saved destinations; throws on corrupt state rather than silently creating locally.
    public func load() async throws {
        accept(try await repository.load())
        isLoaded = true
    }

    /// Observes committed changes until the app-owned observation task is cancelled.
    public func observe() async {
        do {
            for await snapshot in try await repository.updates() {
                accept(snapshot)
                isLoaded = true
            }
        } catch { lastError = error }
    }

    /// Adds or edits a connection without changing the default destination.
    public func save(_ profile: RemoteProfile) async throws {
        guard !busy.contains(profile.id) else { throw RemoteConfigurationError.operationInProgress }
        accept(try await repository.apply(.save(profile)))
    }

    /// Changes the default only; it does not create a workspace.
    public func setDefault(_ location: RemoteLocation) async throws {
        accept(try await repository.apply(.setDefault(location)))
    }

    /// Removes only local connection metadata; provider deletion is explicit and separate.
    public func remove(_ id: UUID) async throws {
        guard busy.insert(id).inserted else { throw RemoteConfigurationError.operationInProgress }
        defer { busy.remove(id) }
        accept(try await repository.apply(.remove(id)))
        states.removeValue(forKey: id)
    }

    /// Refreshes one machine without starting it or blocking other profiles.
    public func refresh(_ id: UUID) async throws {
        let locator = try await cloudLocator(id)
        guard !busy.contains(id) else { return }
        do {
            let status = try await provider.status(locator)
            guard !busy.contains(id), configuration.profiles.contains(where: { $0.id == id }) else { return }
            states[id] = RemoteMachineState(status: status)
        }
        catch { states[id] = .error; lastError = error; throw error }
    }

    /// Starts once, observes until running, then re-enables automatic session reconnect.
    public func start(_ id: UUID) async throws {
        try await changeRunning(true, id: id)
    }

    /// Disables reconnect durably and detaches known workspaces before issuing one provider stop.
    public func stop(_ id: UUID) async throws {
        try await changeRunning(false, id: id)
    }

    /// Deletes cloud resources only when explicitly requested by the Settings confirmation flow.
    public func deleteCompute(_ id: UUID) async throws {
        let locator = try await cloudLocator(id)
        guard busy.insert(id).inserted else { throw RemoteConfigurationError.operationInProgress }
        defer { busy.remove(id) }
        accept(try await repository.apply(.setAutomaticReconnect(id, false)))
        await beforeStop(id)
        do {
            try await provider.delete(locator)
            accept(try await repository.apply(.remove(id)))
            states.removeValue(forKey: id)
        } catch { states[id] = .error; lastError = error; throw error }
    }

    /// Records an entrypoint failure for the shared error presentation.
    public func report(_ error: any Error) { lastError = error }
    /// Dismisses the shared error presentation.
    public func clearError() { lastError = nil }

    /// Holds the machine's lifecycle gate until workspace creation has accepted the connection.
    ///
    /// - Parameters:
    ///   id: Saved machine identity selected when the user requested creation.
    ///   runtime: Verifies the persistent Instacloud runtime before opening SSH.
    ///   confirmStart: Explicit user consent to start an intentionally stopped machine.
    ///   create: Creates the workspace using the prepared SSH alias; never called on failure.
    /// - Returns: False when the user cancels starting the machine.
    /// - Throws: Identity, lifecycle, runtime, transport, or workspace creation errors.
    func withConnection(
        to id: UUID,
        runtime: any RemoteRuntimeServicing,
        confirmStart: @MainActor (RemoteProfile) async -> Bool,
        create: @MainActor (RemoteProfile, String) async throws -> Void
    ) async throws -> Bool {
        if !isLoaded { try await load() }
        guard let profile = configuration.profiles.first(where: { $0.id == id }) else {
            throw RemoteConfigurationError.missingProfile
        }
        guard busy.insert(id).inserted else { throw RemoteConfigurationError.operationInProgress }
        defer { busy.remove(id) }
        let destination: String
        switch profile.target {
        case .ssh(let host):
            destination = host
        case .instacloud(let locator):
            let status = try await provider.status(locator)
            states[id] = RemoteMachineState(status: status)
            if status.isStopped {
                guard await confirmStart(profile) else { return false }
                try await changeRunningWhileOwned(true, id: id, locator: locator)
            } else if !status.isRunning {
                throw InstacloudError.machineNotRunning
            }
            try await runtime.verifyMachine(locator, expectedDigest: nil)
            destination = try await provider.prepareSSH(locator)
        }
        // Start may have changed the durable reconnect flag. Pass the current profile.
        guard let current = configuration.profiles.first(where: { $0.id == id }) else {
            throw RemoteConfigurationError.missingProfile
        }
        try await create(current, destination)
        return true
    }

    private func changeRunning(_ running: Bool, id: UUID) async throws {
        let locator = try await cloudLocator(id)
        guard busy.insert(id).inserted else { throw RemoteConfigurationError.operationInProgress }
        defer { busy.remove(id) }
        try await changeRunningWhileOwned(running, id: id, locator: locator)
    }

    private func changeRunningWhileOwned(_ running: Bool, id: UUID, locator: InstacloudLocator) async throws {
        do {
            // Verify before touching local lifecycle state, and the provider re-verifies before mutation.
            _ = try await provider.verify(locator, requireVolume: false)
            if !running {
                accept(try await repository.apply(.setAutomaticReconnect(id, false)))
                await beforeStop(id)
            }
            states[id] = running ? .starting : .stopping
            try await provider.setRunning(running, locator: locator)
            for attempt in 0..<schedule.attempts {
                try Task.checkCancellation()
                let status = try await provider.status(locator)
                states[id] = RemoteMachineState(status: status)
                if running ? status.isRunning : status.isStopped {
                    if running { accept(try await repository.apply(.setAutomaticReconnect(id, true))) }
                    return
                }
                if attempt + 1 < schedule.attempts { try await schedule.next() }
            }
            throw InstacloudError.transitionTimedOut
        } catch { states[id] = .error; lastError = error; throw error }
    }

    private func cloudLocator(_ id: UUID) async throws -> InstacloudLocator {
        if !isLoaded { try await load() }
        guard let profile = configuration.profiles.first(where: { $0.id == id }),
              case .instacloud(let locator) = profile.target else {
            throw RemoteConfigurationError.missingProfile
        }
        return locator
    }

    private func accept(_ snapshot: RemoteConfiguration) {
        if snapshot.revision >= configuration.revision { configuration = snapshot }
    }
}
