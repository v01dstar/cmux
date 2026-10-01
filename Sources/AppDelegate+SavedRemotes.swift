import CmuxCore
import CmuxCloud
import CmuxRemotes
import Foundation
import AppKit

extension AppDelegate {
    /// Every shortcut/menu entrypoint supplies only its destination and existing local creation policy.
    func performSavedNewWorkspaceAction(
        at location: RemoteLocation?, context: MainWindowContext?, createLocal: @escaping @MainActor () -> Bool
    ) -> Bool {
        guard let remotes else { return false }
        let selectedWorkspaceID = context?.tabManager.selectedTabId
        let initiatingWindow = NSApp.keyWindow
        Task { [weak self] in
            guard let self else { return }
            do {
                if !remotes.locations.isLoaded { try await remotes.locations.load() }
                let destination = location ?? remotes.locations.configuration.defaultLocation
                if case .remote = destination, !ManagedRemoteConnectionsPolicy.isEnabled {
                    throw InstacloudError.unavailable
                }
                try await remotes.workspaces.create(at: destination, confirmStart: { profile in
                    let alert = NSAlert()
                    alert.messageText = String(localized: "menu.remotes.start.title", defaultValue: "Start this remote machine?")
                    alert.informativeText = profile.name
                    alert.addButton(withTitle: String(localized: "menu.remotes.start.confirm", defaultValue: "Start and Create Workspace"))
                    alert.addButton(withTitle: String(localized: "menu.remotes.cancel", defaultValue: "Cancel"))
                    if let window = context.flatMap({ self.resolvedWindow(for: $0) }) {
                        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
                    }
                    return alert.runModal() == .alertFirstButtonReturn
                }, createLocal: {
                    guard createLocal() else { throw RemoteConfigurationError.operationInProgress }
                }, createRemote: { profile, alias in
                    guard ManagedRemoteConnectionsPolicy.isEnabled else { throw CancellationError() }
                    let context = try self.savedRemoteWorkspaceContext(preferred: context,
                        shouldActivate: NSApp.keyWindow === initiatingWindow)
                    var parameters: [String: Any] = ["destination": alias, "title": profile.name,
                        "window_id": context.windowId.uuidString, "focus": true]
                    if case .instacloud = profile.target {
                        parameters["ssh_options"] = ["ControlMaster=no", "ControlPath=none", "ControlPersist=no"]
                        parameters["initial_command"] = "cd /data/workspace && exec /bin/bash -l"
                    }
                    let result = try await TerminalController.shared.openSSHTuiWorkspace(params: parameters,
                        onCreated: { $0.savedRemoteProfileID = profile.id },
                        shouldFocus: {
                            context.tabManager.selectedTabId == selectedWorkspaceID
                                && self.resolvedWindow(for: context)?.isKeyWindow == true
                        })
                    if result["auth_required"] as? Bool == true {
                        throw InstacloudError.sshAuthenticationRequired(alias)
                    }
                    guard let rawID = result["workspace_id"] as? String, let id = UUID(uuidString: rawID),
                          let workspace = Workspace.liveWorkspace(id: id) else {
                        throw InstacloudError.invalidResponse
                    }
                    workspace.savedRemoteProfileID = profile.id
                })
            } catch {
                remotes.locations.report(error)
                let alert = NSAlert()
                alert.messageText = String(localized: "menu.remotes.failed.title", defaultValue: "Could Not Open Workspace")
                alert.informativeText = String(localized: "menu.remotes.failed.message", defaultValue: "Check Remotes in Settings for the connection status and recovery options.")
                if let window = context.flatMap({ self.resolvedWindow(for: $0) }) { await alert.beginSheetModal(for: window) }
                else { alert.runModal() }
            }
        }
        return true
    }

    /// A remote creation without a window must not briefly create a local terminal.
    private func savedRemoteWorkspaceContext(preferred: MainWindowContext?, shouldActivate: Bool) throws -> MainWindowContext {
        if let preferred {
            guard resolvedWindow(for: preferred) != nil else { throw CancellationError() }
            return preferred
        }
        let windowID = createMainWindow(createInitialWorkspace: false, shouldActivate: shouldActivate)
        guard let context = mainWindowContexts.values.first(where: { $0.windowId == windowID }) else {
            throw CancellationError()
        }
        return context
    }

    /// Stops local reconnect activity before the provider receives a stop or delete request.
    func detachSavedRemoteWorkspaces(profileID: UUID) async {
        for context in mainWindowContexts.values {
            for workspace in context.tabManager.tabs where workspace.savedRemoteProfileID == profileID {
                await sshTuiWorkspaceCoordinator.suspend(workspace: workspace)
                workspace.disconnectRemoteConnection()
            }
        }
    }

    /// Restore remains detached until saved stop intent and fresh provider state have been checked.
    func restoreSavedRemoteWorkspace(_ workspace: Workspace, configuration: WorkspaceRemoteConfiguration) async {
        guard let remotes, let profileID = workspace.savedRemoteProfileID,
              ManagedRemoteConnectionsPolicy.isEnabled else { return }
        do {
            _ = try await remotes.workspaces.reconnect(profileID: profileID) { [weak workspace] _, destination in
                guard let workspace, workspace.savedRemoteProfileID == profileID,
                      workspace.remoteConfiguration == configuration,
                      configuration.destination == destination,
                      ManagedRemoteConnectionsPolicy.isEnabled else { return }
                workspace.configureRemoteConnection(configuration, autoConnect: true)
            }
        } catch { remotes.locations.report(error) }
    }
}
