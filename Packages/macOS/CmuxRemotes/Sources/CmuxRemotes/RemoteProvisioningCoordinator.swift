import Foundation
import Observation

/// Creates and resumes one journaled compute operation without repeating uncertain creation requests.
@MainActor @Observable
public final class RemoteProvisioningCoordinator {
    /// Operations currently advancing; independent machines do not block each other.
    public private(set) var busy: Set<UUID> = []
    private let repository: any RemoteConfigurationStoring
    private let provider: any InstacloudProviding
    private let runtime: any RemoteRuntimeServicing
    private let schedule: RemoteStatusSchedule
    private var connectingExisting: Set<String> = []

    /// Creates the coordinator with injectable provider, runtime verification, and durable journal storage.
    public init(repository: any RemoteConfigurationStoring, provider: any InstacloudProviding,
                runtime: any RemoteRuntimeServicing, schedule: RemoteStatusSchedule = RemoteStatusSchedule()) {
        self.repository = repository
        self.provider = provider
        self.runtime = runtime
        self.schedule = schedule
    }

    /// Reserves a stable service name and records the plan before any cloud resource is created.
    public func plan(name: String, organizationID: String, projectID: String, branch: String) async throws -> UUID {
        let bundle = try await runtime.bundle(digest: nil)
        try await runtime.validate(bundle)
        let id = UUID()
        let serviceName = "cmux-" + id.uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
        let operation = RemoteProvisioningOperation(id: id, organizationID: organizationID, projectID: projectID,
            branch: branch, serviceName: serviceName, bundleDigest: bundle.digest, name: name)
        _ = try await repository.apply(.saveOperation(operation))
        return id
    }

    /// Reconciles an operation, deploying only the original bundle and saving a connection after readiness.
    @discardableResult
    public func resume(_ id: UUID) async throws -> RemoteProfile {
        guard busy.insert(id).inserted else { throw RemoteConfigurationError.operationInProgress }
        defer { busy.remove(id) }
        let snapshot = try await repository.load()
        guard var operation = snapshot.operations.first(where: { $0.id == id }) else {
            throw RemoteConfigurationError.missingProfile
        }
        if operation.stage == .ready,
           let saved = snapshot.profiles.first(where: { $0.id == operation.profileID }) {
            // Reopening completed progress must not wake a stopped machine or re-enable reconnect.
            return saved
        }
        let bundle = try await runtime.bundle(digest: operation.bundleDigest)
        guard bundle.digest == operation.bundleDigest else { throw InstacloudError.bundleChanged }
        try await runtime.validate(bundle)

        if operation.stage == .planned || operation.stage == .creating {
            let inventory = try await provider.computes(projectID: operation.projectID, branch: operation.branch)
            if let existing = inventory.first(where: { $0.name == operation.serviceName }) {
                guard operation.stage == .creating else { throw InstacloudError.nameConflict }
                guard existing.projectID == operation.projectID,
                      operation.serviceID == nil || operation.serviceID == existing.id else {
                    throw InstacloudError.identityChanged
                }
                operation.serviceID = existing.id
            } else {
                // A lost create response is not evidence that the provider did nothing. Keep Resume
                // available, but do not create a second machine while that outcome remains unknown.
                guard operation.stage == .planned else { throw InstacloudError.creationUncertain }
                operation.stage = .creating
                _ = try await repository.apply(.saveOperation(operation))
                do {
                    let created = try await provider.create(operation)
                    guard created.projectID == operation.projectID, created.name == operation.serviceName else {
                        throw InstacloudError.identityChanged
                    }
                    operation.serviceID = created.id
                } catch let error as InstacloudError {
                    if case .approvalRequired = error {
                        // The provider explicitly refused to execute. Preserve identical request inputs
                        // so Resume can retry after the user authorizes the original request.
                        operation.stage = .planned
                        _ = try await repository.apply(.saveOperation(operation))
                    }
                    throw error
                }
            }
            operation.stage = .created
            _ = try await repository.apply(.saveOperation(operation))
        }
        guard let serviceID = operation.serviceID else { throw InstacloudError.invalidResponse }
        let locator = InstacloudLocator(organizationID: operation.organizationID, projectID: operation.projectID,
            branch: operation.branch, serviceID: serviceID, serviceName: operation.serviceName)
        _ = try await provider.verify(locator, requireVolume: true)
        if operation.stage == .created {
            operation.stage = .deploying
            _ = try await repository.apply(.saveOperation(operation))
            try await runtime.validate(bundle)
            try await provider.deploy(locator, bundleDirectory: bundle.directory)
            operation.stage = .deployed
            _ = try await repository.apply(.saveOperation(operation))
        }
        // A deploy timeout may still have succeeded. Verify the expected marker rather than replacing
        // a running image or issuing the same deploy again merely because the client lost its response.
        try await runtime.verifyMachine(locator, expectedDigest: operation.bundleDigest)
        operation.stage = .ready
        _ = try await repository.apply(.saveOperation(operation))
        let profile = RemoteProfile(id: operation.profileID, name: operation.name, target: .instacloud(locator))
        _ = try await repository.apply(.save(profile))
        return profile
    }

    /// Adds an existing compute only after checking identity, volume, and compatible runtime.
    /// Existing machines are never redeployed or have their image replaced during this flow.
    /// - Parameters:
    ///   name: Display name for the saved connection.
    ///   locator: Immutable provider identity selected by the user.
    ///   confirmStart: Explicit consent before starting an intentionally stopped machine.
    /// - Returns: The saved profile, or nil when the user declines starting it.
    /// - Throws: Identity, runtime, lifecycle, or persistence errors.
    public func connectExisting(name: String, locator: InstacloudLocator,
        confirmStart: @MainActor (InstacloudLocator) async -> Bool = { _ in false }
    ) async throws -> RemoteProfile? {
        guard connectingExisting.insert(locator.serviceID).inserted else {
            throw RemoteConfigurationError.operationInProgress
        }
        defer { connectingExisting.remove(locator.serviceID) }
        let existing = try await repository.load().profiles.first {
            guard case .instacloud(let target) = $0.target else { return false }
            return target.projectID == locator.projectID && target.branch == locator.branch && target.serviceID == locator.serviceID
        }
        // Re-adding a saved machine is idempotent and cannot wake it or race its
        // saved profile's separate lifecycle gate.
        if let existing { return existing }
        _ = try await provider.verify(locator, requireVolume: true)
        let status = try await provider.status(locator)
        if status.isStopped {
            guard await confirmStart(locator) else { return nil }
            try await provider.setRunning(true, locator: locator)
            var running = false
            for attempt in 0..<schedule.attempts {
                try Task.checkCancellation()
                if try await provider.status(locator).isRunning { running = true; break }
                if attempt + 1 < schedule.attempts { try await schedule.next() }
            }
            guard running else { throw InstacloudError.transitionTimedOut }
        } else if !status.isRunning {
            throw InstacloudError.machineNotRunning
        }
        try await runtime.verifyMachine(locator, expectedDigest: nil)
        let profile = RemoteProfile(name: name, target: .instacloud(locator))
        _ = try await repository.apply(.save(profile))
        return profile
    }
}
