import Foundation

/// Provider seam shared by discovery, settings lifecycle actions, and workspace creation.
public protocol InstacloudProviding: Sendable {
    /// Reads the current CLI account identity.
    func account() async throws -> InstacloudAccountStatus
    /// Starts browser-based login without importing credentials into cmux.
    func login() async throws
    /// Lists accessible organizations.
    func organizations() async throws -> [InstacloudResource]
    /// Lists projects in the selected organization.
    func projects(organizationID: String) async throws -> [InstacloudResource]
    /// Lists branches so discovery can choose the project's actual default.
    func branches(projectID: String) async throws -> [InstacloudResource]
    /// Lists current compute identities on a branch.
    func computes(projectID: String, branch: String) async throws -> [InstacloudCompute]
    /// Verifies identity and, when requested, the persistent volume.
    func verify(_ locator: InstacloudLocator, requireVolume: Bool) async throws -> InstacloudCompute
    /// Reads provider lifecycle state after verifying the resource identity.
    func status(_ locator: InstacloudLocator) async throws -> InstacloudComputeStatus
    /// Issues one start or stop request, never a polling loop of repeated mutations.
    func setRunning(_ running: Bool, locator: InstacloudLocator) async throws
    /// Deletes the exact saved resource after confirmation in the caller.
    func delete(_ locator: InstacloudLocator) async throws
    /// Creates the operation's named compute with a persistent volume.
    func create(_ operation: RemoteProvisioningOperation) async throws -> InstacloudCompute
    /// Deploys a verified runtime bundle to the exact resource.
    func deploy(_ locator: InstacloudLocator, bundleDirectory: URL) async throws
    /// Prepares the CLI-managed short-lived SSH connection and returns its alias.
    func prepareSSH(_ locator: InstacloudLocator) async throws -> String
}
