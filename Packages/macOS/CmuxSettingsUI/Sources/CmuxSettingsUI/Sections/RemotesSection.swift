import CmuxRemotes
import SwiftUI

/// Saved workspace destinations and provider lifecycle controls.
@MainActor
public struct RemotesSection: View {
    private let model: RemotesSettingsModel
    @State private var showsAdd = false
    @State private var pendingStop: RemoteProfile?
    @State private var pendingDelete: RemoteProfile?

    /// Creates the section using the same locations model as the new-workspace menu.
    /// - Parameter model: App-owned Settings workflow.
    public init(model: RemotesSettingsModel) { self.model = model }

    public var body: some View {
        SettingsSectionHeader(String(localized: "settings.section.remotes", defaultValue: "Remotes"), section: .remotes)
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "settings.remotes.intro", defaultValue: "Choose where new workspaces open. Closing a workspace leaves its remote machine running."))
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Label(String(localized: "settings.remotes.local", defaultValue: "Local"), systemImage: "desktopcomputer")
                    Spacer()
                    defaultButton(.local)
                }
                ForEach(model.locations.configuration.profiles) { profile in
                    Divider()
                    profileRow(profile)
                }
                ForEach(model.locations.configuration.operations.filter { $0.stage != .ready }) { operation in
                    Divider()
                    HStack {
                        Label(operation.name, systemImage: "cloud")
                        Spacer()
                        if model.provisioning.busy.contains(operation.id) { ProgressView().controlSize(.small) }
                        Button(String(localized: "settings.remotes.resume", defaultValue: "Resume Setup")) {
                            Task { await model.resume(operation.id) }
                        }.disabled(model.provisioning.busy.contains(operation.id))
                    }
                }
                if let error = model.locations.lastError { RemoteOperationErrorView(error: error) }
                HStack {
                    Button(String(localized: "settings.remotes.add", defaultValue: "Add Remote…")) { showsAdd = true }
                        .accessibilityIdentifier("SettingsRemotesAdd")
                    Spacer()
                    Button(String(localized: "settings.remotes.refresh", defaultValue: "Refresh")) { refresh() }
                }
            }.padding(14)
        }
        .task { refresh() }
        .sheet(isPresented: $showsAdd) { AddRemoteSheet(model: model) }
        .confirmationDialog(String(localized: "settings.remotes.stop.title", defaultValue: "Stop this machine?"),
            isPresented: Binding(get: { pendingStop != nil }, set: { if !$0 { pendingStop = nil } }), titleVisibility: .visible) {
            Button(String(localized: "settings.remotes.stop", defaultValue: "Stop"), role: .destructive) {
                if let profile = pendingStop { run { try await model.locations.stop(profile.id) } }
                pendingStop = nil
            }
        } message: {
            Text(String(localized: "settings.remotes.stop.message", defaultValue: "Running processes will end. Files on the persistent volume are kept. Starting again will not restore those processes."))
        }
        .confirmationDialog(String(localized: "settings.remotes.delete.title", defaultValue: "Permanently delete this cloud machine?"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button(String(localized: "settings.remotes.delete", defaultValue: "Delete Cloud Machine…"), role: .destructive) {
                if let profile = pendingDelete { run { try await model.locations.deleteCompute(profile.id) } }
                pendingDelete = nil
            }
        } message: {
            Text(String(localized: "settings.remotes.delete.message", defaultValue: "The machine and its stored files will be permanently deleted. This cannot be undone."))
        }
    }

    private func profileRow(_ profile: RemoteProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(profile.name, systemImage: "server.rack")
                Spacer()
                if model.locations.busy.contains(profile.id) { ProgressView().controlSize(.small) }
                defaultButton(.remote(profile.id))
            }
            HStack {
                if case .instacloud = profile.target {
                    Text(stateLabel(model.locations.states[profile.id] ?? .unknown)).foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "settings.remotes.start", defaultValue: "Start")) {
                        run { try await model.locations.start(profile.id) }
                    }.disabled(model.locations.states[profile.id] != .stopped)
                    Button(String(localized: "settings.remotes.stop", defaultValue: "Stop")) { pendingStop = profile }
                        .disabled(model.locations.states[profile.id] != .running)
                } else { Spacer() }
                Menu {
                    Button(String(localized: "settings.remotes.remove", defaultValue: "Remove Connection")) {
                        run { try await model.locations.remove(profile.id) }
                    }
                    if case .instacloud = profile.target {
                        Divider()
                        Button(String(localized: "settings.remotes.delete", defaultValue: "Delete Cloud Machine…"), role: .destructive) {
                            pendingDelete = profile
                        }
                    }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel(String(localized: "settings.remotes.actions", defaultValue: "Remote Actions"))
                .menuStyle(.borderlessButton).fixedSize()
            }.disabled(model.locations.busy.contains(profile.id))
        }
    }

    private func defaultButton(_ location: RemoteLocation) -> some View {
        Button {
            run { try await model.locations.setDefault(location) }
        } label: {
            Label(String(localized: "settings.remotes.default", defaultValue: "Default"),
                  systemImage: model.locations.configuration.defaultLocation == location ? "checkmark.circle.fill" : "circle")
        }.buttonStyle(.plain)
        .accessibilityValue(model.locations.configuration.defaultLocation == location
            ? String(localized: "settings.remotes.selected", defaultValue: "Selected")
            : String(localized: "settings.remotes.notSelected", defaultValue: "Not selected"))
    }

    private func refresh() {
        run {
            try await model.locations.load()
            for profile in model.locations.configuration.profiles {
                if case .instacloud = profile.target {
                    Task { do { try await model.locations.refresh(profile.id) } catch { model.locations.report(error) } }
                }
            }
        }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        model.locations.clearError()
        Task { do { try await action() } catch { model.locations.report(error) } }
    }

    private func stateLabel(_ state: RemoteMachineState) -> String {
        switch state {
        case .unknown: return String(localized: "settings.remotes.state.unknown", defaultValue: "Status unknown")
        case .starting: return String(localized: "settings.remotes.state.starting", defaultValue: "Starting")
        case .running: return String(localized: "settings.remotes.state.running", defaultValue: "Running")
        case .stopping: return String(localized: "settings.remotes.state.stopping", defaultValue: "Stopping")
        case .stopped: return String(localized: "settings.remotes.state.stopped", defaultValue: "Stopped")
        case .error: return String(localized: "settings.remotes.state.error", defaultValue: "Could not update status")
        }
    }
}
