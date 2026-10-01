import Foundation
@testable import CmuxRemotes

actor DiscoveryTestProvider: InstacloudProviding {
    private var heldOrganization: String?
    private var pending: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private var arrived = false
    var branchRequests: [String] = []

    func hold(_ organization: String) { heldOrganization = organization }
    func waitUntilHeld() async {
        if arrived { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { pending?.resume(); pending = nil }
    func account() throws -> InstacloudAccountStatus {
        try decode(#"{"user":{"email":"test@example.com"},"project":{"projectId":"p-one","orgId":"one","branch":"stale"}}"#)
    }
    func login() {}
    func organizations() throws -> [InstacloudResource] {
        try decode(#"[{"id":"one","name":"One"},{"id":"two","name":"Two"}]"#)
    }
    func projects(organizationID: String) async throws -> [InstacloudResource] {
        if heldOrganization == organizationID {
            await withCheckedContinuation { continuation in
                pending = continuation
                arrived = true
                observer?.resume()
                observer = nil
            }
        }
        return try decode("[{\"id\":\"p-\(organizationID)\",\"name\":\"Project\"}]")
    }
    func branches(projectID: String) throws -> [InstacloudResource] {
        try decode(#"[{"id":"b-other","name":"other"},{"id":"b-default","name":"main","is_default":true}]"#)
    }
    func computes(projectID: String, branch: String) throws -> [InstacloudCompute] {
        branchRequests.append(branch)
        return try decode("[{\"id\":\"service-\(projectID)\",\"name\":\"dev\",\"type\":\"compute\",\"project_id\":\"\(projectID)\"}]")
    }
    func verify(_ locator: InstacloudLocator, requireVolume: Bool) throws -> InstacloudCompute { throw InstacloudError.unavailable }
    func status(_ locator: InstacloudLocator) throws -> InstacloudComputeStatus { throw InstacloudError.unavailable }
    func setRunning(_ running: Bool, locator: InstacloudLocator) throws { throw InstacloudError.unavailable }
    func delete(_ locator: InstacloudLocator) throws { throw InstacloudError.unavailable }
    func create(_ operation: RemoteProvisioningOperation) throws -> InstacloudCompute { throw InstacloudError.unavailable }
    func deploy(_ locator: InstacloudLocator, bundleDirectory: URL) throws { throw InstacloudError.unavailable }
    func prepareSSH(_ locator: InstacloudLocator) throws -> String { throw InstacloudError.unavailable }
    private func decode<T: Decodable>(_ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }
}
