import CmuxFoundation
import CmuxRemotes
import Foundation

/// Constructs the shared remote models once for Settings, workspace creation, and session restore.
@MainActor
struct RemotesComposition {
    let locations: RemoteLocationsModel
    let settings: RemotesSettingsModel
    let workspaces: RemoteWorkspaceCoordinator

    init(directory: URL, client: URL, beforeStop: @escaping @MainActor (UUID) async -> Void) {
        let files = FileManager()
        let commands = CommandRunner()
        let repository = RemoteConfigurationRepository(fileURL: directory.appendingPathComponent("remotes.json"), fileManager: files)
        let provider = InstacloudCLI(commands: commands, directory: directory.appendingPathComponent("projects"),
            agentMode: ProcessInfo.processInfo.environment["CODEX_THREAD_ID"] != nil, fileManager: files)
        let runtime = RemoteRuntimeRepository(commands: commands, probes: provider, client: client,
            directory: directory.appendingPathComponent("runtime-bundles"),
            sourceRepository: URL(string: "https://github.com/manaflow-ai/cmux.git")!, fileManager: files)
        let locations = RemoteLocationsModel(repository: repository, provider: provider, beforeStop: beforeStop)
        self.locations = locations
        self.settings = RemotesSettingsModel(locations: locations, discovery: RemoteDiscoveryModel(provider: provider),
            provisioning: RemoteProvisioningCoordinator(repository: repository, provider: provider, runtime: runtime))
        self.workspaces = RemoteWorkspaceCoordinator(locations: locations, runtime: runtime)
    }
}
