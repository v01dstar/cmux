import Foundation

/// Routes every new-workspace entrypoint through the durable default or an explicit menu choice.
@MainActor
public final class RemoteWorkspaceCoordinator {
    private let locations: RemoteLocationsModel
    private let runtime: any RemoteRuntimeServicing

    /// Creates a router sharing the Settings model and runtime verification service.
    /// - Parameters:
    ///   locations: App-owned source of truth for destinations and lifecycle gates.
    ///   runtime: Verifies a cloud machine before a workspace can connect.
    public init(locations: RemoteLocationsModel, runtime: any RemoteRuntimeServicing) {
        self.locations = locations
        self.runtime = runtime
    }

    /// Creates at the current default unless the caller explicitly selected a menu destination.
    ///
    /// The selected workspace has no influence on this decision. Selecting a destination here
    /// never changes the default; Settings and menu checkboxes use `setDefault` separately.
    ///
    /// - Parameters:
    ///   location: Explicit menu destination, or nil for the shortcut/default action.
    ///   confirmStart: Presents start confirmation for an intentionally stopped compute.
    ///   createLocal: Creates a local workspace using the existing local layout policy.
    ///   createRemote: Creates a workspace bound to the saved profile and prepared SSH alias.
    /// - Returns: False if the user declines to start the machine.
    /// - Throws: Configuration, provider, runtime, or creation failure; never falls back locally.
    @discardableResult
    public func create(
        at location: RemoteLocation? = nil,
        confirmStart: @MainActor (RemoteProfile) async -> Bool,
        createLocal: @MainActor () async throws -> Void,
        createRemote: @MainActor (RemoteProfile, String) async throws -> Void
    ) async throws -> Bool {
        do {
            if !locations.isLoaded { try await locations.load() }
            switch location ?? locations.configuration.defaultLocation {
            case .local:
                try await createLocal()
                return true
            case .remote(let id):
                return try await locations.withConnection(
                    to: id, runtime: runtime, confirmStart: confirmStart, create: createRemote
                )
            }
        } catch {
            locations.report(error)
            throw error
        }
    }
}
