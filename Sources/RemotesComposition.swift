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
        #if DEBUG
        // Fork contributors need the public commit that built their local client;
        // the runtime service still validates the URL and exact binary identity.
        let sourceRepository = ProcessInfo.processInfo.environment["CMUX_REMOTES_RUNTIME_SOURCE_REPOSITORY"]
            ?? "https://github.com/manaflow-ai/cmux.git"
        #else
        let sourceRepository = "https://github.com/manaflow-ai/cmux.git"
        #endif
        let runtime = RemoteRuntimeRepository(commands: commands, probes: provider, client: client,
            directory: directory.appendingPathComponent("runtime-bundles"),
            sourceRepository: URL(string: sourceRepository) ?? URL(fileURLWithPath: "/invalid-runtime-source"), fileManager: files)
        let locations = RemoteLocationsModel(repository: repository, provider: provider, beforeStop: beforeStop)
        self.locations = locations
        self.settings = RemotesSettingsModel(locations: locations, discovery: RemoteDiscoveryModel(provider: provider),
            provisioning: RemoteProvisioningCoordinator(repository: repository, provider: provider, runtime: runtime))
        self.workspaces = RemoteWorkspaceCoordinator(locations: locations, runtime: runtime)
    }
}
