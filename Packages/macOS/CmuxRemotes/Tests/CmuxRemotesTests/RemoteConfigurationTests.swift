import Foundation
import Testing
@testable import CmuxRemotes

struct RemoteConfigurationTests {
    @Test func newInstallationDefaultsToLocal() throws {
        let configuration = RemoteConfiguration()
        try configuration.validate()
        #expect(configuration.defaultLocation == .local)
    }

    @Test func explicitDefaultSurvivesProfileUpdatesAndUnrelatedRemoval() throws {
        let first = RemoteProfile(name: "dev", target: .ssh(destination: "dev"))
        let second = RemoteProfile(name: "test", target: .ssh(destination: "test"))
        var state = RemoteConfiguration()
        try state.apply(.save(first))
        try state.apply(.save(second))
        try state.apply(.setDefault(.remote(first.id)))
        var renamed = first
        renamed.name = "renamed"
        try state.apply(.save(renamed))
        try state.apply(.remove(second.id))
        #expect(state.defaultLocation == .remote(first.id))
        try state.apply(.remove(first.id))
        #expect(state.defaultLocation == .local)
    }

    @Test func editingProfileCannotMoveWorkspacesToDifferentMachine() throws {
        let profile = RemoteProfile(name: "dev", target: .ssh(destination: "original"))
        var state = RemoteConfiguration(profiles: [profile])
        var replacement = profile
        replacement.target = .ssh(destination: "other-machine")
        #expect(throws: RemoteConfigurationError.profileIdentityChanged) { try state.apply(.save(replacement)) }
        #expect(state.profiles == [profile])
    }

    @Test func selectingMissingRemoteLeavesStateUntouched() throws {
        var state = RemoteConfiguration()
        let original = state
        #expect(throws: RemoteConfigurationError.missingProfile) {
            try state.apply(.setDefault(.remote(UUID())))
        }
        #expect(state == original)
    }

    @Test func stoppingPreservesDefaultAndDisablesReconnectAcrossReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("remotes.json")
        let store = RemoteConfigurationRepository(fileURL: url, fileManager: FileManager())
        let profile = RemoteProfile(name: "dev", target: .ssh(destination: "dev"))
        _ = try await store.apply(.save(profile))
        _ = try await store.apply(.setDefault(.remote(profile.id)))
        _ = try await store.apply(.setAutomaticReconnect(profile.id, false))
        let reloaded = try await RemoteConfigurationRepository(fileURL: url, fileManager: FileManager()).load()
        #expect(reloaded.defaultLocation == .remote(profile.id))
        #expect(reloaded.profiles.first?.automaticReconnectEnabled == false)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test func concurrentChangesDoNotLoseSavedMachines() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RemoteConfigurationRepository(fileURL: directory.appendingPathComponent("remotes.json"), fileManager: FileManager())
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    _ = try await store.apply(.save(RemoteProfile(name: "host-\(index)", target: .ssh(destination: "host-\(index)"))))
                }
            }
            try await group.waitForAll()
        }
        let state = try await store.load()
        #expect(state.profiles.count == 20)
        #expect(state.revision == 20)
    }

    @Test func corruptFileIsNotReplaced() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("not JSON".utf8)
        try data.write(to: url)
        let store = RemoteConfigurationRepository(fileURL: url, fileManager: FileManager())
        await #expect(throws: (any Error).self) { try await store.load() }
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func provisioningRetryCannotChangeResourceOrBundleIdentity() throws {
        var operation = RemoteProvisioningOperation(organizationID: "org", projectID: "project", branch: "main", serviceName: "fixed-name", bundleDigest: "sha256")
        var state = RemoteConfiguration()
        try state.apply(.saveOperation(operation))
        operation.stage = .creating
        try state.apply(.saveOperation(operation))
        operation.serviceID = "original"
        operation.stage = .created
        try state.apply(.saveOperation(operation))
        operation.serviceID = "replacement"
        #expect(throws: RemoteConfigurationError.operationIdentityChanged) { try state.apply(.saveOperation(operation)) }
        #expect(state.operations.first?.serviceID == "original")
    }
}
