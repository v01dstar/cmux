import Foundation
@testable import CmuxRemotes

actor ProvisioningTestProvider: InstacloudProviding {
    var inventory: [InstacloudCompute] = []
    var creations = 0
    var deployments = 0
    var loseCreateResponse = false
    var createNeverVisible = false
    var requireApproval = false
    var loseDeployResponse = false

    func configure(lostCreate: Bool = false, neverVisible: Bool = false, approval: Bool = false, lostDeploy: Bool = false) {
        loseCreateResponse = lostCreate; createNeverVisible = neverVisible
        requireApproval = approval; loseDeployResponse = lostDeploy
    }
    func insert(name: String) throws { inventory.append(try service(name: name)) }
    private func service(name: String) throws -> InstacloudCompute {
        let data = try JSONSerialization.data(withJSONObject: ["id": "service", "project_id": "project", "type": "compute", "name": name, "volume_gib": 10, "volume_mount_path": "/data"])
        return try JSONDecoder().decode(InstacloudCompute.self, from: data)
    }
    func computes(projectID: String, branch: String) -> [InstacloudCompute] { inventory }
    func create(_ operation: RemoteProvisioningOperation) throws -> InstacloudCompute {
        creations += 1
        if requireApproval { requireApproval = false; throw InstacloudError.approvalRequired("approval-1") }
        let result = try service(name: operation.serviceName)
        if !createNeverVisible { inventory.append(result) }
        if loseCreateResponse { loseCreateResponse = false; throw InstacloudError.timedOut }
        return result
    }
    func verify(_ locator: InstacloudLocator, requireVolume: Bool) throws -> InstacloudCompute {
        guard let match = inventory.first(where: { $0.name == locator.serviceName && $0.id == locator.serviceID }) else { throw InstacloudError.identityChanged }
        return match
    }
    func deploy(_ locator: InstacloudLocator, bundleDirectory: URL) throws {
        deployments += 1
        if loseDeployResponse { loseDeployResponse = false; throw InstacloudError.timedOut }
    }
    func account() throws -> InstacloudAccountStatus { throw InstacloudError.unavailable }
    func login() throws { throw InstacloudError.unavailable }
    func organizations() throws -> [InstacloudResource] { throw InstacloudError.unavailable }
    func projects(organizationID: String) throws -> [InstacloudResource] { throw InstacloudError.unavailable }
    func branches(projectID: String) throws -> [InstacloudResource] { throw InstacloudError.unavailable }
    func status(_ locator: InstacloudLocator) throws -> InstacloudComputeStatus { throw InstacloudError.unavailable }
    func setRunning(_ running: Bool, locator: InstacloudLocator) throws { throw InstacloudError.unavailable }
    func delete(_ locator: InstacloudLocator) throws { throw InstacloudError.unavailable }
    func prepareSSH(_ locator: InstacloudLocator) throws -> String { throw InstacloudError.unavailable }
}
