import Foundation
import Testing
@testable import CmuxRemotes

@MainActor
struct RemoteProvisioningTests {
    @Test func lostCreateResponseReconcilesWithoutSecondMachine() async throws {
        let fixture = RemoteProvisioningFixture(); defer { fixture.cleanup() }
        await fixture.provider.configure(lostCreate: true)
        let id = try await fixture.plan()
        await #expect(throws: InstacloudError.timedOut) { try await fixture.coordinator.resume(id) }
        #expect(try await fixture.store.load().operations.first?.stage == .creating)
        let profile = try await fixture.coordinator.resume(id)
        #expect(profile.name == "My remote")
        #expect(await fixture.provider.creations == 1)
        #expect(await fixture.provider.deployments == 1)
        #expect(try await fixture.store.load().defaultLocation == .local)
        #expect(try await fixture.store.load().operations.first?.stage == .ready)
    }

    @Test func reopeningCompletedProgressDoesNotReenableStoppedMachine() async throws {
        let fixture = RemoteProvisioningFixture(); defer { fixture.cleanup() }
        let id = try await fixture.plan()
        let profile = try await fixture.coordinator.resume(id)
        _ = try await fixture.store.apply(.setAutomaticReconnect(profile.id, false))
        let reopened = try await fixture.coordinator.resume(id)
        #expect(!reopened.automaticReconnectEnabled)
        #expect(await fixture.provider.creations == 1)
        #expect(await fixture.provider.deployments == 1)
    }

    @Test func plannedNameConflictCannotBeAdopted() async throws {
        let fixture = RemoteProvisioningFixture(); defer { fixture.cleanup() }
        let id = try await fixture.plan()
        let operation = try #require(try await fixture.store.load().operations.first)
        try await fixture.provider.insert(name: operation.serviceName)
        await #expect(throws: InstacloudError.nameConflict) { try await fixture.coordinator.resume(id) }
        #expect(await fixture.provider.creations == 0)
        #expect(await fixture.provider.deployments == 0)
    }

    @Test func uncertainInvisibleCreateDoesNotRetryMutation() async throws {
        let fixture = RemoteProvisioningFixture(); defer { fixture.cleanup() }
        await fixture.provider.configure(lostCreate: true, neverVisible: true)
        let id = try await fixture.plan()
        await #expect(throws: InstacloudError.timedOut) { try await fixture.coordinator.resume(id) }
        await #expect(throws: InstacloudError.creationUncertain) { try await fixture.coordinator.resume(id) }
        #expect(await fixture.provider.creations == 1)
    }

    @Test func approvalCanResumeSameRequestWithoutAutoApproving() async throws {
        let fixture = RemoteProvisioningFixture(); defer { fixture.cleanup() }
        await fixture.provider.configure(approval: true)
        let id = try await fixture.plan()
        let original = try #require(try await fixture.store.load().operations.first)
        await #expect(throws: InstacloudError.approvalRequired("approval-1")) { try await fixture.coordinator.resume(id) }
        #expect(try await fixture.store.load().operations.first?.stage == .planned)
        _ = try await fixture.coordinator.resume(id)
        #expect(try await fixture.store.load().operations.first?.serviceName == original.serviceName)
    }

    @Test func lostDeployResponseChecksRuntimeRatherThanRedeploying() async throws {
        let fixture = RemoteProvisioningFixture(); defer { fixture.cleanup() }
        await fixture.provider.configure(lostDeploy: true)
        let id = try await fixture.plan()
        await #expect(throws: InstacloudError.timedOut) { try await fixture.coordinator.resume(id) }
        #expect(try await fixture.store.load().operations.first?.stage == .deploying)
        _ = try await fixture.coordinator.resume(id)
        #expect(await fixture.provider.deployments == 1)
    }

    @Test func modifiedBundleCannotCreateResources() async throws {
        let fixture = RemoteProvisioningFixture(); defer { fixture.cleanup() }
        let id = try await fixture.plan()
        await fixture.runtime.changeBundle()
        await #expect(throws: InstacloudError.bundleChanged) { try await fixture.coordinator.resume(id) }
        #expect(await fixture.provider.creations == 0)
    }

    @Test func incompatibleExistingMachineIsNotReplaced() async throws {
        let fixture = RemoteProvisioningFixture(); defer { fixture.cleanup() }
        try await fixture.provider.insert(name: "existing")
        await fixture.runtime.rejectRuntime()
        let locator = InstacloudLocator(organizationID: "org", projectID: "project", branch: "main", serviceID: "service", serviceName: "existing")
        await #expect(throws: InstacloudError.incompatibleRuntime) {
            try await fixture.coordinator.connectExisting(name: "Existing", locator: locator)
        }
        #expect(await fixture.provider.deployments == 0)
        #expect(try await fixture.store.load().profiles.isEmpty)
    }
}
