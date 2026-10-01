import Foundation

/// A recoverable create/deploy operation, journaled before each externally visible mutation.
public struct RemoteProvisioningOperation: Codable, Equatable, Identifiable, Sendable {
    /// Stable operation identity across retries and application restarts.
    public let id: UUID
    /// User-visible label preserved across a restart during provisioning.
    public let name: String
    /// Local profile identity reserved before a compute exists.
    public let profileID: UUID
    /// Organization that owns the target project.
    public let organizationID: String
    /// Target project identity.
    public let projectID: String
    /// Target branch, pinned for the lifetime of this operation.
    public let branch: String
    /// Generated once; reconciliation may adopt this name only after create was issued.
    public let serviceName: String
    /// Digest of the immutable runtime bundle used by this operation.
    public let bundleDigest: String
    /// Provider identity, recorded as soon as creation or reconciliation succeeds.
    public var serviceID: String?
    /// Last durable stage, retaining uncertainty after a command times out.
    public var stage: Stage

    /// Persisted provisioning stages.
    public enum Stage: String, Codable, Sendable {
        /// No cloud creation request has been issued; a same-name service is a conflict.
        case planned
        /// Creation was issued; a lost response must be reconciled before retrying.
        case creating
        /// The immutable service identity is known.
        case created
        /// Runtime deployment was issued and may still be running.
        case deploying
        /// Deployment completed; runtime readiness still needs verification.
        case deployed
        /// The expected runtime and persistent volume were verified.
        case ready
    }

    /// Reserves a stable compute name and runtime digest before issuing any command.
    public init(id: UUID = UUID(), profileID: UUID = UUID(), organizationID: String,
                projectID: String, branch: String, serviceName: String, bundleDigest: String, name: String? = nil) {
        self.id = id
        self.name = name ?? serviceName
        self.profileID = profileID
        self.organizationID = organizationID
        self.projectID = projectID
        self.branch = branch
        self.serviceName = serviceName
        self.bundleDigest = bundleDigest
        self.serviceID = nil
        self.stage = .planned
    }
}
