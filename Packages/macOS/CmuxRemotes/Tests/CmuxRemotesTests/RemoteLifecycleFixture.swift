import Foundation
@testable import CmuxRemotes

@MainActor
struct RemoteLifecycleFixture {
        let directory: URL
        let profile: RemoteProfile
        let provider: LifecycleTestProvider
        let model: RemoteLocationsModel
        init(statuses: [(String, String)], reconnect: Bool = true) async throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let repository = RemoteConfigurationRepository(fileURL: directory.appendingPathComponent("remotes.json"), fileManager: FileManager())
            profile = RemoteProfile(name: "dev", target: .instacloud(InstacloudLocator(organizationID: "org", projectID: "project", branch: "main", serviceID: "service", serviceName: "dev")), automaticReconnectEnabled: reconnect)
            _ = try await repository.apply(.save(profile))
            _ = try await repository.apply(.setDefault(.remote(profile.id)))
            provider = LifecycleTestProvider(repository: repository, statuses: statuses)
            model = RemoteLocationsModel(repository: repository, provider: provider, schedule: RemoteStatusSchedule(attempts: max(1, statuses.count), next: {}))
        }
        func removeFiles() { try? FileManager.default.removeItem(at: directory) }
    }
