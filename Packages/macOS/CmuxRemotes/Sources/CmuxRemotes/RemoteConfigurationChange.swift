import Foundation

/// Atomic mutations accepted by the remote configuration repository.
public enum RemoteConfigurationChange: Sendable {
    /// Adds a profile or updates the profile with the same stable identity.
    case save(RemoteProfile)
    /// Changes only the default destination, without creating a workspace.
    case setDefault(RemoteLocation)
    /// Removes the saved connection; deleting provider resources is a separate operation.
    case remove(UUID)
    /// Enables or disables automatic reconnect for one saved machine.
    case setAutomaticReconnect(UUID, Bool)
    /// Journals a provisioning stage, preserving the original operation identity.
    case saveOperation(RemoteProvisioningOperation)
    /// Discards a completed or explicitly abandoned operation record.
    case removeOperation(UUID)
}
