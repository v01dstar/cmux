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
    @State private var showsStartConfirmation = false
    @State private var startContinuation: CheckedContinuation<Bool, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "settings.remotes.add.title", defaultValue: "Add Remote"))
                .font(.title2.bold())
            Picker(String(localized: "settings.remotes.connection", defaultValue: "Connection"), selection: $usesSSH) {
                Text(String(localized: "settings.remotes.instacloud", defaultValue: "Instacloud Machine")).tag(false)
                Text(String(localized: "settings.remotes.ssh", defaultValue: "SSH Host")).tag(true)
            }.pickerStyle(.segmented).disabled(submitting)
            TextField(String(localized: "settings.remotes.name", defaultValue: "Name"), text: $name)
                .accessibilityIdentifier("RemoteDisplayName")
                .disabled(submitting)
            if usesSSH {
                TextField(String(localized: "settings.remotes.host", defaultValue: "SSH host or user@host"), text: $destination)
                    .accessibilityIdentifier("RemoteSSHHost")
                    .disabled(submitting)
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
        .alert(String(localized: "settings.remotes.add.start.title", defaultValue: "Start this machine to add it?"), isPresented: $showsStartConfirmation) {
            Button(String(localized: "settings.remotes.start", defaultValue: "Start")) { resolveStart(true) }
            Button(String(localized: "settings.remotes.cancel", defaultValue: "Cancel"), role: .cancel) { resolveStart(false) }
        } message: {
            Text(String(localized: "settings.remotes.add.start.message", defaultValue: "cmux must start this machine to verify its runtime. This may incur compute charges. Its existing deployment will not be replaced."))
        }
        .onChange(of: showsStartConfirmation) { _, shown in
            if !shown { resolveStart(false) }
        }
        .onDisappear { resolveStart(false) }
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
                else {
                    guard try await model.addInstacloud(name: selectedName, computeID: selectedCompute, confirmStart: { _ in
                        await withCheckedContinuation { continuation in
                            startContinuation = continuation
                            showsStartConfirmation = true
                        }
                    }) else { return }
                }
                dismiss()
            } catch { self.error = error }
        }
    }

    private func resolveStart(_ approved: Bool) {
        let continuation = startContinuation
        startContinuation = nil
        showsStartConfirmation = false
        continuation?.resume(returning: approved)
    }
}
