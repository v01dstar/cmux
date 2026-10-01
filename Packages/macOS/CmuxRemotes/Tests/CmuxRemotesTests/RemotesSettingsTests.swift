import Testing
@testable import CmuxRemotes

@MainActor
struct RemotesSettingsTests {
    @Test func addingSSHTrimsFieldsAndKeepsDefaultLocal() async throws {
        let fixture = RemoteProvisioningFixture()
        defer { fixture.cleanup() }
        let locations = RemoteLocationsModel(repository: fixture.store, provider: fixture.provider)
        let model = RemotesSettingsModel(locations: locations,
            discovery: RemoteDiscoveryModel(provider: fixture.provider), provisioning: fixture.coordinator)
        try await model.addSSH(name: "  Build Server  ", destination: " builder@example.com ")
        #expect(locations.configuration.defaultLocation == .local)
        #expect(locations.configuration.profiles.first?.name == "Build Server")
        #expect(locations.configuration.profiles.first?.target == .ssh(destination: "builder@example.com"))
        #expect(await fixture.provider.creations == 0)
    }

    @Test func invalidSSHDoesNotPersistConnection() async throws {
        let fixture = RemoteProvisioningFixture()
        defer { fixture.cleanup() }
        let locations = RemoteLocationsModel(repository: fixture.store, provider: fixture.provider)
        let model = RemotesSettingsModel(locations: locations,
            discovery: RemoteDiscoveryModel(provider: fixture.provider), provisioning: fixture.coordinator)
        await #expect(throws: RemoteConfigurationError.invalidProfile) {
            try await model.addSSH(name: "Server", destination: "-oProxyCommand=unexpected")
        }
        #expect(locations.configuration.profiles.isEmpty)
    }

    @Test func resumeSurfacesUncertaintyAndReusesSavedOperation() async throws {
        let fixture = RemoteProvisioningFixture()
        defer { fixture.cleanup() }
        let locations = RemoteLocationsModel(repository: fixture.store, provider: fixture.provider)
        let model = RemotesSettingsModel(locations: locations,
            discovery: RemoteDiscoveryModel(provider: fixture.provider), provisioning: fixture.coordinator)
        let id = try await fixture.plan()
        await fixture.provider.configure(lostCreate: true)
        await model.resume(id)
        #expect(locations.lastError as? InstacloudError == .timedOut)
        #expect(locations.configuration.operations.first?.id == id)
        #expect(locations.configuration.profiles.isEmpty)
        await model.resume(id)
        #expect(locations.lastError == nil)
        #expect(locations.configuration.profiles.count == 1)
        #expect(locations.configuration.defaultLocation == .local)
        #expect(await fixture.provider.creations == 1)
    }
}
