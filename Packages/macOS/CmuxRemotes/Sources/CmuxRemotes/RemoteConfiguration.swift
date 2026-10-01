import Foundation

/// The durable machine inventory and single default used by every workspace-creation entrypoint.
public struct RemoteConfiguration: Codable, Equatable, Sendable {
    /// On-disk format version, rejected if newer than this reader supports.
    public var version: Int = 1
    /// Monotonically increasing mutation revision used to reject delayed observations.
    public var revision: UInt64 = 0
    /// Saved machines in display order.
    public var profiles: [RemoteProfile]
    /// User-selected default; opening a different location never changes it.
    public var defaultLocation: RemoteLocation
    /// Recoverable provider operations, persisted before issuing cloud writes.
    public var operations: [RemoteProvisioningOperation]

    /// Creates configuration; a fresh install defaults to Local.
    public init(profiles: [RemoteProfile] = [], defaultLocation: RemoteLocation = .local,
                operations: [RemoteProvisioningOperation] = []) {
        self.profiles = profiles
        self.defaultLocation = defaultLocation
        self.operations = operations
    }

    /// Applies a validated mutation; a rejected change leaves this value untouched.
    public mutating func apply(_ change: RemoteConfigurationChange) throws {
        var next = self
        switch change {
        case .save(let profile):
            if let index = next.profiles.firstIndex(where: { $0.id == profile.id }) {
                guard next.profiles[index].target == profile.target else {
                    throw RemoteConfigurationError.profileIdentityChanged
                }
                next.profiles[index] = profile
            } else {
                next.profiles.append(profile)
            }
        case .setDefault(let location):
            next.defaultLocation = location
        case .remove(let id):
            next.profiles.removeAll { $0.id == id }
            if next.defaultLocation == .remote(id) { next.defaultLocation = .local }
        case .setAutomaticReconnect(let id, let enabled):
            guard let index = next.profiles.firstIndex(where: { $0.id == id }) else {
                throw RemoteConfigurationError.missingProfile
            }
            next.profiles[index].automaticReconnectEnabled = enabled
        case .saveOperation(let operation):
            if let index = next.operations.firstIndex(where: { $0.id == operation.id }) {
                let previous = next.operations[index]
                guard previous.profileID == operation.profileID,
                      previous.serviceName == operation.serviceName,
                      previous.projectID == operation.projectID,
                      previous.organizationID == operation.organizationID,
                      previous.branch == operation.branch,
                      previous.bundleDigest == operation.bundleDigest,
                      previous.serviceID == nil || previous.serviceID == operation.serviceID else {
                    throw RemoteConfigurationError.operationIdentityChanged
                }
                next.operations[index] = operation
            } else {
                next.operations.append(operation)
            }
        case .removeOperation(let id):
            next.operations.removeAll { $0.id == id }
        }
        try next.validate()
        next.revision += 1
        self = next
    }

    /// Rejects unsupported or inconsistent state instead of overwriting it with an empty inventory.
    public func validate() throws {
        guard version == 1 else { throw RemoteConfigurationError.unsupportedVersion }
        guard Set(profiles.map(\.id)).count == profiles.count,
              Set(operations.map(\.id)).count == operations.count else {
            throw RemoteConfigurationError.duplicateIdentity
        }
        if case .remote(let id) = defaultLocation,
           !profiles.contains(where: { $0.id == id }) {
            throw RemoteConfigurationError.missingProfile
        }
        for profile in profiles {
            guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RemoteConfigurationError.invalidProfile
            }
            switch profile.target {
            case .ssh(let destination):
                guard !destination.isEmpty, !destination.hasPrefix("-"),
                      !destination.contains(where: { $0.isWhitespace || $0.isNewline }) else {
                    throw RemoteConfigurationError.invalidProfile
                }
            case .instacloud(let locator):
                guard [locator.organizationID, locator.projectID, locator.branch,
                       locator.serviceID, locator.serviceName].allSatisfy({ !$0.isEmpty }) else {
                    throw RemoteConfigurationError.invalidProfile
                }
            }
        }
    }
}
