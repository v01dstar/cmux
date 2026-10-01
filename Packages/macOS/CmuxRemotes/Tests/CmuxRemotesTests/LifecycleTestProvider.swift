import Foundation
@testable import CmuxRemotes

actor LifecycleTestProvider: InstacloudProviding {
    let repository: any RemoteConfigurationStoring
    var samples: [(String, String)]
    var mutations: [Bool] = []
    var reconnectAtMutation: [Bool] = []
    var observations = 0
    var deletions = 0
    init(repository: any RemoteConfigurationStoring, statuses: [(String, String)]) {
        self.repository = repository
        self.samples = statuses
    }
    func verify(_ locator: InstacloudLocator, requireVolume: Bool) throws -> InstacloudCompute {
        try JSONDecoder().decode(InstacloudCompute.self, from: Data(#"{"id":"service","name":"dev","type":"compute","project_id":"project"}"#.utf8))
    }
    func status(_ locator: InstacloudLocator) throws -> InstacloudComputeStatus {
        observations += 1
        let next = samples.removeFirst()
        let data = try JSONSerialization.data(withJSONObject: ["state": next.0, "desiredState": next.1])
        return try JSONDecoder().decode(InstacloudComputeStatus.self, from: data)
    }
    func setRunning(_ running: Bool, locator: InstacloudLocator) async throws {
        mutations.append(running)
        reconnectAtMutation.append(try await repository.load().profiles.first!.automaticReconnectEnabled)
    }
    func delete(_ locator: InstacloudLocator) { deletions += 1 }
    func account() throws -> InstacloudAccountStatus { throw InstacloudError.unavailable }
    func login() throws { throw InstacloudError.unavailable }
    func organizations() throws -> [InstacloudResource] { throw InstacloudError.unavailable }
    func projects(organizationID: String) throws -> [InstacloudResource] { throw InstacloudError.unavailable }
    func branches(projectID: String) throws -> [InstacloudResource] { throw InstacloudError.unavailable }
    func computes(projectID: String, branch: String) throws -> [InstacloudCompute] { throw InstacloudError.unavailable }
    func create(_ operation: RemoteProvisioningOperation) throws -> InstacloudCompute { throw InstacloudError.unavailable }
    func deploy(_ locator: InstacloudLocator, bundleDirectory: URL) throws { throw InstacloudError.unavailable }
    func prepareSSH(_ locator: InstacloudLocator) throws -> String { throw InstacloudError.unavailable }
}
