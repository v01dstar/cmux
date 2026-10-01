import Foundation
import Observation

/// Owns the add-remote flow while sharing saved locations with the workspace menu.
@MainActor @Observable
public final class RemotesSettingsModel {
    /// Shared durable locations and machine lifecycle actions.
    public let locations: RemoteLocationsModel
    /// Account and inventory choices for Instacloud.
    public let discovery: RemoteDiscoveryModel
    /// Recoverable creation progress, retained when Settings closes.
    public let provisioning: RemoteProvisioningCoordinator
    /// Prevents duplicate submissions from the add form.
    public private(set) var isAdding = false

    /// Creates the Settings flow from app-owned domain models.
    /// - Parameters:
    ///   locations: Shared saved locations.
    ///   discovery: Account and inventory discovery.
    ///   provisioning: Durable create/connect workflow.
    public init(locations: RemoteLocationsModel, discovery: RemoteDiscoveryModel,
                provisioning: RemoteProvisioningCoordinator) {
        self.locations = locations
        self.discovery = discovery
        self.provisioning = provisioning
    }

    /// Saves an existing SSH host without making it the default.
    /// - Parameters:
    ///   name: User-facing machine name.
    ///   destination: SSH host alias or user@host understood by the user's SSH configuration.
    /// - Throws: Invalid input or persistence errors.
    public func addSSH(name: String, destination: String) async throws {
        try await locations.save(RemoteProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            target: .ssh(destination: destination.trimmingCharacters(in: .whitespacesAndNewlines))))
    }

    /// Connects a selected existing compute or journals and creates a new one.
    /// - Parameters:
    ///   name: User-visible connection label.
    ///   computeID: Selected existing compute, or nil to create a new machine.
    /// - Throws: Selection, runtime, approval, provisioning, or persistence errors.
    public func addInstacloud(name: String, computeID: String?) async throws {
        guard !isAdding else { throw RemoteConfigurationError.operationInProgress }
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, !discovery.isLoading,
              let organizationID = discovery.organizationID, let projectID = discovery.projectID,
              let branch = discovery.branch else { throw RemoteConfigurationError.invalidProfile }
        isAdding = true
        defer { isAdding = false }
        do {
            if let computeID {
                _ = try await provisioning.connectExisting(name: label, locator: discovery.locator(for: computeID))
            } else {
                let id = try await provisioning.plan(name: label, organizationID: organizationID,
                                                     projectID: projectID, branch: branch)
                // Surface the journal immediately, including when a later command needs approval.
                try await locations.load()
                _ = try await provisioning.resume(id)
            }
            try await locations.load()
        } catch {
            try? await locations.load()
            locations.report(error)
            throw error
        }
    }

    /// Resumes the same journaled operation; it does not create a replacement request.
    /// - Parameter id: The operation to reconcile after failure or human approval.
    public func resume(_ id: UUID) async {
        locations.clearError()
        do { _ = try await provisioning.resume(id); try await locations.load() }
        catch { try? await locations.load(); locations.report(error) }
    }
}
