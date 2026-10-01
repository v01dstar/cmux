import Foundation
import Testing
@testable import CmuxRemotes

@MainActor
struct RemoteWorkspaceCoordinatorTests {
    @Test func unloadedDefaultRoutesRemoteWithoutLocalFallback() async throws {
        let fixture = try await RemoteLifecycleFixture(statuses: [("running", "running")])
        defer { fixture.removeFiles() }
        let router = RemoteWorkspaceCoordinator(locations: fixture.model, runtime: ProvisioningTestRuntime())
        var local = 0
        var remote: UUID?
        let created = try await router.create(confirmStart: { _ in Issue.record("Unexpected prompt"); return false },
            createLocal: { local += 1 }, createRemote: { profile, host in
                remote = profile.id
                #expect(host == "dev.insta")
            })
        #expect(created)
        #expect(local == 0)
        #expect(remote == fixture.profile.id)
    }

    @Test func explicitLocalDoesNotChangeDefaultOrTouchProvider() async throws {
        let fixture = try await RemoteLifecycleFixture(statuses: [])
        defer { fixture.removeFiles() }
        let router = RemoteWorkspaceCoordinator(locations: fixture.model, runtime: ProvisioningTestRuntime())
        var local = 0
        try await router.create(at: .local, confirmStart: { _ in false }, createLocal: { local += 1 },
                                createRemote: { _, _ in Issue.record("Unexpected remote") })
        #expect(local == 1)
        #expect(fixture.model.configuration.defaultLocation == .remote(fixture.profile.id))
        #expect(await fixture.provider.observations == 0)
    }

    @Test func decliningStartCreatesNothingAndPreservesStoppedProfile() async throws {
        let fixture = try await RemoteLifecycleFixture(statuses: [("suspended", "stopped")], reconnect: false)
        defer { fixture.removeFiles() }
        let router = RemoteWorkspaceCoordinator(locations: fixture.model, runtime: ProvisioningTestRuntime())
        var prompted = false
        let created = try await router.create(confirmStart: { _ in prompted = true; return false },
            createLocal: { Issue.record("Unexpected local") }, createRemote: { _, _ in Issue.record("Unexpected remote") })
        #expect(prompted)
        #expect(!created)
        #expect(await fixture.provider.mutations.isEmpty)
        #expect(await fixture.provider.sshPreparations == 0)
        #expect(fixture.model.configuration.profiles.first?.automaticReconnectEnabled == false)
        #expect(fixture.model.busy.isEmpty)
    }

    @Test func acceptedStartCreatesAfterRunningAndHoldsLifecycleGate() async throws {
        let fixture = try await RemoteLifecycleFixture(statuses: [("suspended", "stopped"), ("running", "running")], reconnect: false)
        defer { fixture.removeFiles() }
        let router = RemoteWorkspaceCoordinator(locations: fixture.model, runtime: ProvisioningTestRuntime())
        var remote = 0
        try await router.create(confirmStart: { _ in
            await #expect(throws: RemoteConfigurationError.operationInProgress) {
                try await fixture.model.deleteCompute(fixture.profile.id)
            }
            return true
        }, createLocal: { Issue.record("Unexpected local") }, createRemote: { profile, _ in
            #expect(profile.automaticReconnectEnabled)
            await #expect(throws: RemoteConfigurationError.operationInProgress) {
                try await fixture.model.stop(profile.id)
            }
            remote += 1
        })
        #expect(remote == 1)
        #expect(await fixture.provider.mutations == [true])
        #expect(await fixture.provider.deletions == 0)
        #expect(fixture.model.busy.isEmpty)
    }

    @Test func incompatibleRuntimeDoesNotPrepareSSHOrCreateLocal() async throws {
        let fixture = try await RemoteLifecycleFixture(statuses: [("running", "running")])
        defer { fixture.removeFiles() }
        let runtime = ProvisioningTestRuntime()
        await runtime.rejectRuntime()
        let router = RemoteWorkspaceCoordinator(locations: fixture.model, runtime: runtime)
        await #expect(throws: InstacloudError.incompatibleRuntime) {
            try await router.create(confirmStart: { _ in false }, createLocal: { Issue.record("Unexpected fallback") },
                                    createRemote: { _, _ in Issue.record("Unexpected remote") })
        }
        #expect(await fixture.provider.sshPreparations == 0)
        #expect(fixture.model.lastError as? InstacloudError == .incompatibleRuntime)
        #expect(fixture.model.busy.isEmpty)
    }

    @Test func transitioningMachineDoesNotCreateOrSendAnotherStart() async throws {
        let fixture = try await RemoteLifecycleFixture(statuses: [("starting", "running")])
        defer { fixture.removeFiles() }
        let router = RemoteWorkspaceCoordinator(locations: fixture.model, runtime: ProvisioningTestRuntime())
        await #expect(throws: InstacloudError.machineNotRunning) {
            try await router.create(confirmStart: { _ in Issue.record("Unexpected prompt"); return true },
                createLocal: { Issue.record("Unexpected fallback") }, createRemote: { _, _ in Issue.record("Unexpected remote") })
        }
        #expect(await fixture.provider.mutations.isEmpty)
    }

    @Test func explicitSSHDoesNotChangeLocalDefault() async throws {
        let fixture = try await RemoteLifecycleFixture(statuses: [])
        defer { fixture.removeFiles() }
        let ssh = RemoteProfile(name: "Server", target: .ssh(destination: "developer@server"))
        try await fixture.model.save(ssh)
        try await fixture.model.setDefault(.local)
        let router = RemoteWorkspaceCoordinator(locations: fixture.model, runtime: ProvisioningTestRuntime())
        var remote = 0
        try await router.create(at: .remote(ssh.id), confirmStart: { _ in false },
            createLocal: { Issue.record("Unexpected local") }, createRemote: { profile, host in
                #expect(profile.id == ssh.id)
                #expect(host == "developer@server")
                remote += 1
            })
        #expect(remote == 1)
        #expect(fixture.model.configuration.defaultLocation == .local)
        #expect(await fixture.provider.observations == 0)
    }
    @Test func restoreHonorsDurableStopIntentBeforeAnyProviderCall() async throws {
        let fixture = try await RemoteLifecycleFixture(statuses: [], reconnect: false)
        defer { fixture.removeFiles() }
        let router = RemoteWorkspaceCoordinator(locations: fixture.model, runtime: ProvisioningTestRuntime())
        let connected = try await router.reconnect(profileID: fixture.profile.id) { _, _ in
            Issue.record("Stopped workspace must stay detached")
        }
        #expect(!connected)
        #expect(await fixture.provider.observations == 0)
        #expect(await fixture.provider.sshPreparations == 0)
    }

    @Test func restoreNeverStartsMachineStoppedOutsideCmux() async throws {
        let fixture = try await RemoteLifecycleFixture(statuses: [("suspended", "stopped")])
        defer { fixture.removeFiles() }
        let router = RemoteWorkspaceCoordinator(locations: fixture.model, runtime: ProvisioningTestRuntime())
        let connected = try await router.reconnect(profileID: fixture.profile.id) { _, _ in
            Issue.record("Externally stopped machine must not connect")
        }
        #expect(!connected)
        #expect(await fixture.provider.mutations.isEmpty)
    }

}
