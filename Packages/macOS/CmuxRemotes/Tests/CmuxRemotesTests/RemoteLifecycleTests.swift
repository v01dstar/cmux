import Foundation
import Testing
@testable import CmuxRemotes

@MainActor
struct RemoteLifecycleTests {
    @Test func stopDisablesReconnectBeforeMutationAndPollsWithoutRepeatingStop() async throws {
        let fixture = try await RemoteLifecycleFixture(statuses: [
            ("suspended", "running"), ("stopping", "stopped"), ("suspended", "stopped"),
        ])
        defer { fixture.removeFiles() }
        try await fixture.model.stop(fixture.profile.id)
        #expect(await fixture.provider.mutations == [false])
        #expect(await fixture.provider.reconnectAtMutation == [false])
        #expect(await fixture.provider.observations == 3)
        #expect(fixture.model.states[fixture.profile.id] == .stopped)
        #expect(fixture.model.configuration.defaultLocation == .remote(fixture.profile.id))
    }

    @Test func startReenablesReconnectOnlyAfterRunning() async throws {
        let fixture = try await RemoteLifecycleFixture(statuses: [("starting", "running"), ("running", "running")], reconnect: false)
        defer { fixture.removeFiles() }
        try await fixture.model.start(fixture.profile.id)
        #expect(await fixture.provider.mutations == [true])
        #expect(await fixture.provider.reconnectAtMutation == [false])
        #expect(fixture.model.configuration.profiles.first?.automaticReconnectEnabled == true)
        #expect(fixture.model.states[fixture.profile.id] == .running)
    }

    @Test func timeoutLeavesReconnectDisabledAndNeverResendsMutation() async throws {
        let fixture = try await RemoteLifecycleFixture(statuses: [("suspended", "running")])
        defer { fixture.removeFiles() }
        await #expect(throws: InstacloudError.transitionTimedOut) { try await fixture.model.stop(fixture.profile.id) }
        #expect(await fixture.provider.mutations == [false])
        #expect(fixture.model.configuration.profiles.first?.automaticReconnectEnabled == false)
        #expect(fixture.model.states[fixture.profile.id] == .error)
    }

    @Test func removingConnectionDoesNotDeleteOrStopCompute() async throws {
        let fixture = try await RemoteLifecycleFixture(statuses: [])
        defer { fixture.removeFiles() }
        try await fixture.model.load()
        try await fixture.model.remove(fixture.profile.id)
        #expect(fixture.model.configuration.defaultLocation == .local)
        #expect(await fixture.provider.mutations.isEmpty)
        #expect(await fixture.provider.deletions == 0)
    }

    @Test func explicitDeletionRemovesDefaultOnlyAfterProviderSucceeds() async throws {
        let fixture = try await RemoteLifecycleFixture(statuses: [])
        defer { fixture.removeFiles() }
        try await fixture.model.deleteCompute(fixture.profile.id)
        #expect(await fixture.provider.deletions == 1)
        #expect(fixture.model.configuration.profiles.isEmpty)
        #expect(fixture.model.configuration.defaultLocation == .local)
    }
}
