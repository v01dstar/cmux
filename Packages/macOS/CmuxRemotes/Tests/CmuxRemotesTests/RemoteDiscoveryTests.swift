import Testing
@testable import CmuxRemotes

@MainActor
struct RemoteDiscoveryTests {
    @Test func selectsActualDefaultBranchRatherThanFirstOrStaleCLISelection() async throws {
        let provider = DiscoveryTestProvider()
        let model = RemoteDiscoveryModel(provider: provider)
        await model.refresh()
        #expect(model.account?.user?.email == "test@example.com")
        #expect(model.organizationID == "one")
        #expect(model.projectID == "p-one")
        #expect(model.branch == "main")
        #expect(await provider.branchRequests == ["main"])
        let locator = try model.locator(for: "service-p-one")
        #expect(locator.projectID == "p-one")
        #expect(locator.serviceID == "service-p-one")
        #expect(model.lastError == nil)
    }

    @Test func oldOrganizationResponseCannotReplaceNewSelection() async throws {
        let provider = DiscoveryTestProvider()
        let model = RemoteDiscoveryModel(provider: provider)
        await model.refresh()
        await provider.hold("two")
        let oldRequest = Task { await model.selectOrganization("two") }
        await provider.waitUntilHeld()
        #expect(model.projects.isEmpty)
        #expect(model.computes.isEmpty)
        #expect(throws: RemoteConfigurationError.missingProfile) { try model.locator(for: "service-p-one") }
        await model.selectOrganization("one")
        #expect(!model.isLoading)
        await provider.release()
        await oldRequest.value
        #expect(model.organizationID == "one")
        #expect(model.projectID == "p-one")
        #expect(model.computes.first?.id == "service-p-one")
        #expect(!model.isLoading)
    }

    @Test func branchSelectionReloadsInventoryAndUnknownSelectionIsIgnored() async throws {
        let provider = DiscoveryTestProvider()
        let model = RemoteDiscoveryModel(provider: provider)
        await model.refresh()
        await model.selectBranch("other")
        #expect(model.branch == "other")
        #expect(try model.locator(for: "service-p-one").branch == "other")
        await model.selectProject("foreign-project")
        #expect(model.projectID == "p-one")
        #expect(await provider.branchRequests == ["main", "other"])
    }
}
