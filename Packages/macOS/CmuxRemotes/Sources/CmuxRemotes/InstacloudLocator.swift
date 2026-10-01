import Foundation

/// Identifies an Instacloud compute without storing authentication material.
public struct InstacloudLocator: Codable, Equatable, Sendable {
    /// Organization that owns the project.
    public let organizationID: String
    /// Stable project identifier.
    public let projectID: String
    /// Branch containing the compute.
    public let branch: String
    /// Immutable service identifier; names alone must never authorize a mutation.
    public let serviceID: String
    /// Current compute name used by the CLI, checked against ``serviceID`` before use.
    public var serviceName: String

    /// Creates an exact provider resource locator.
    public init(organizationID: String, projectID: String, branch: String, serviceID: String, serviceName: String) {
        self.organizationID = organizationID
        self.projectID = projectID
        self.branch = branch
        self.serviceID = serviceID
        self.serviceName = serviceName
    }
}
