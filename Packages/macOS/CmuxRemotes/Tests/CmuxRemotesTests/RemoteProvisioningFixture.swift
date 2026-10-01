import Foundation
@testable import CmuxRemotes

@MainActor
struct RemoteProvisioningFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store: RemoteConfigurationRepository
    let provider = ProvisioningTestProvider()
    let runtime = ProvisioningTestRuntime()
    let coordinator: RemoteProvisioningCoordinator
    init() {
        store = RemoteConfigurationRepository(fileURL: directory.appendingPathComponent("remotes.json"), fileManager: FileManager())
        coordinator = RemoteProvisioningCoordinator(repository: store, provider: provider, runtime: runtime)
    }
    func plan() async throws -> UUID {
        try await coordinator.plan(name: "My remote", organizationID: "org", projectID: "project", branch: "main")
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
