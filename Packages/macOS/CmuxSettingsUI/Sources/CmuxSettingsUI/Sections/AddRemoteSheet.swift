import CmuxRemotes
import SwiftUI

/// Adds an SSH alias or a discovered Instacloud machine without changing the default location.
@MainActor
struct AddRemoteSheet: View {
    let model: RemotesSettingsModel
    @Environment(\.dismiss) private var dismiss
    @State private var usesSSH = false
    @State private var name = ""
    @State private var destination = ""
    @State private var computeID = ""
    @State private var submitting = false
    @State private var error: (any Error)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "settings.remotes.add.title", defaultValue: "Add Remote"))
                .font(.title2.bold())
            Picker(String(localized: "settings.remotes.connection", defaultValue: "Connection"), selection: $usesSSH) {
                Text(String(localized: "settings.remotes.instacloud", defaultValue: "Instacloud Machine")).tag(false)
                Text(String(localized: "settings.remotes.ssh", defaultValue: "SSH Host")).tag(true)
            }.pickerStyle(.segmented)
            TextField(String(localized: "settings.remotes.name", defaultValue: "Name"), text: $name)
                .accessibilityIdentifier("RemoteDisplayName")
            if usesSSH {
                TextField(String(localized: "settings.remotes.host", defaultValue: "SSH host or user@host"), text: $destination)
                    .accessibilityIdentifier("RemoteSSHHost")
            } else {
                cloudFields
            }
            if let error { RemoteOperationErrorView(error: error) }
            HStack {
                Button(String(localized: "settings.remotes.cancel", defaultValue: "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if submitting { ProgressView().controlSize(.small) }
                Button(String(localized: "settings.remotes.add.confirm", defaultValue: "Add")) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("RemoteAddConfirm")
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24).frame(width: 480)
        .task { await model.discovery.refresh() }
        .onChange(of: model.discovery.projectID) { _, _ in computeID = "" }
        .onChange(of: model.discovery.branch) { _, _ in computeID = "" }
        .interactiveDismissDisabled(submitting)
    }

    private var cloudFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let email = model.discovery.account?.user?.email { Text(email).textSelection(.enabled) }
                Spacer()
                Button(String(localized: "settings.remotes.signIn", defaultValue: "Sign In")) {
                    Task { await model.discovery.login() }
                }.disabled(model.discovery.isLoading || submitting)
                Button(String(localized: "settings.remotes.refresh", defaultValue: "Refresh")) {
                    Task { await model.discovery.refresh() }
                }.disabled(model.discovery.isLoading || submitting)
            }
            Picker(String(localized: "settings.remotes.organization", defaultValue: "Organization"),
                   selection: Binding(get: { model.discovery.organizationID ?? "" }, set: { id in
                       Task { await model.discovery.selectOrganization(id) }
                   })) {
                ForEach(model.discovery.organizations) { Text($0.name).tag($0.id) }
            }.disabled(submitting)
            Picker(String(localized: "settings.remotes.project", defaultValue: "Project"),
                   selection: Binding(get: { model.discovery.projectID ?? "" }, set: { id in
                       Task { await model.discovery.selectProject(id) }
                   })) {
                ForEach(model.discovery.projects) { Text($0.name).tag($0.id) }
            }.disabled(submitting)
            Picker(String(localized: "settings.remotes.branch", defaultValue: "Branch"),
                   selection: Binding(get: { model.discovery.branch ?? "" }, set: { branch in
                       Task { await model.discovery.selectBranch(branch) }
                   })) {
                ForEach(model.discovery.branches) { Text($0.name).tag($0.name) }
            }.disabled(submitting)
            Picker(String(localized: "settings.remotes.machine", defaultValue: "Machine"), selection: $computeID) {
                Text(String(localized: "settings.remotes.newMachine", defaultValue: "Create a New Machine")).tag("")
                ForEach(model.discovery.computes) { Text($0.name).tag($0.id) }
            }.disabled(model.discovery.isLoading || submitting)
            if computeID.isEmpty {
                Text(String(localized: "settings.remotes.billing", defaultValue: "A new machine with persistent storage will be created in this project and billed to your Instacloud account."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if model.discovery.isLoading { ProgressView().controlSize(.small) }
            if let error = model.discovery.lastError { RemoteOperationErrorView(error: error) }
        }
    }

    private var canSubmit: Bool {
        guard !submitting, !model.isAdding, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if usesSSH { return !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !model.discovery.isLoading && model.discovery.lastError == nil && model.discovery.branch != nil
    }

    private func submit() {
        submitting = true
        error = nil
        let selectedSSH = usesSSH
        let selectedName = name
        let selectedHost = destination
        let selectedCompute = computeID.isEmpty ? nil : computeID
        Task {
            defer { submitting = false }
            do {
                if selectedSSH { try await model.addSSH(name: selectedName, destination: selectedHost) }
                else { try await model.addInstacloud(name: selectedName, computeID: selectedCompute) }
                dismiss()
            } catch { self.error = error }
        }
    }
}
