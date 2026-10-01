import Foundation
import Observation

/// Account and project pickers for adding Instacloud remotes without exposing provider IDs in forms.
@MainActor @Observable
public final class RemoteDiscoveryModel {
    /// Current signed-in CLI account; credentials remain owned by the CLI.
    public private(set) var account: InstacloudAccountStatus?
    /// Accessible organizations for the account.
    public private(set) var organizations: [InstacloudResource] = []
    /// Projects in the selected organization.
    public private(set) var projects: [InstacloudResource] = []
    /// Branches in the selected project.
    public private(set) var branches: [InstacloudResource] = []
    /// Existing computes on the selected branch.
    public private(set) var computes: [InstacloudCompute] = []
    /// Selected organization, cleared when account discovery restarts.
    public private(set) var organizationID: String?
    /// Selected project, cleared immediately when the organization changes.
    public private(set) var projectID: String?
    /// Selected branch name, initially the project's declared default.
    public private(set) var branch: String?
    /// Whether the currently selected inventory is loading.
    public private(set) var isLoading = false
    /// Most recent current-selection error; stale requests cannot replace it.
    public private(set) var lastError: (any Error)?

    private let provider: any InstacloudProviding
    private var generation = UUID()

    /// Creates discovery with the app's provider service.
    /// - Parameter provider: CLI account and inventory access.
    public init(provider: any InstacloudProviding) { self.provider = provider }

    /// Refreshes login and inventory, suggesting CLI-linked organization and project when accessible.
    public func refresh() async {
        let request = begin()
        account = nil
        organizations = []
        organizationID = nil
        clearProjects()
        do {
            let identity = try await provider.account()
            guard request == generation else { return }
            account = identity
            guard identity.user != nil else { throw InstacloudError.loginRequired }
            let available = try await provider.organizations()
            guard request == generation else { return }
            organizations = available
            organizationID = available.first(where: { $0.id == identity.project?.orgId })?.id ?? available.first?.id
            try await loadProjects(request: request, preferredProject: identity.project?.projectId)
        } catch { fail(error, request: request) }
        finish(request)
    }

    /// Launches the CLI browser login, then reloads its authoritative identity.
    public func login() async {
        let request = begin()
        do {
            try await provider.login()
            guard request == generation else { return }
            await refresh()
        } catch { fail(error, request: request); finish(request) }
    }

    /// Changes organization and invalidates all dependent selections before network I/O.
    /// - Parameter id: An organization from the current inventory.
    public func selectOrganization(_ id: String) async {
        guard organizations.contains(where: { $0.id == id }) else { return }
        let request = begin()
        organizationID = id
        clearProjects()
        do { try await loadProjects(request: request, preferredProject: nil) }
        catch { fail(error, request: request) }
        finish(request)
    }

    /// Changes project and selects its actual default branch, not a CLI directory's stale selection.
    /// - Parameter id: A project from the current organization.
    public func selectProject(_ id: String) async {
        guard projects.contains(where: { $0.id == id }) else { return }
        let request = begin()
        projectID = id
        clearBranches()
        do { try await loadBranches(request: request) }
        catch { fail(error, request: request) }
        finish(request)
    }

    /// Changes branch and clears the old compute list immediately.
    /// - Parameter name: A branch from the selected project.
    public func selectBranch(_ name: String) async {
        guard branches.contains(where: { $0.name == name }) else { return }
        let request = begin()
        branch = name
        computes = []
        do { try await loadComputes(request: request) }
        catch { fail(error, request: request) }
        finish(request)
    }

    /// Captures immutable identity for the user's chosen existing compute.
    /// - Parameter id: A compute from the completed current inventory.
    /// - Returns: A locator whose project and service identity agree.
    /// - Throws: If selection is loading, missing, or inconsistent with provider inventory.
    public func locator(for id: String) throws -> InstacloudLocator {
        guard !isLoading, let organizationID, let projectID, let branch,
              let compute = computes.first(where: { $0.id == id }) else {
            throw RemoteConfigurationError.missingProfile
        }
        guard compute.projectID == projectID else { throw InstacloudError.identityChanged }
        return InstacloudLocator(organizationID: organizationID, projectID: projectID,
                                branch: branch, serviceID: compute.id, serviceName: compute.name)
    }

    private func loadProjects(request: UUID, preferredProject: String?) async throws {
        guard let organizationID else { return }
        let available = try await provider.projects(organizationID: organizationID)
        guard request == generation else { return }
        projects = available
        projectID = available.first(where: { $0.id == preferredProject })?.id ?? available.first?.id
        try await loadBranches(request: request)
    }

    private func loadBranches(request: UUID) async throws {
        guard let projectID else { return }
        let available = try await provider.branches(projectID: projectID)
        guard request == generation else { return }
        branches = available
        branch = available.first(where: { $0.isDefault == true })?.name ?? available.first?.name
        try await loadComputes(request: request)
    }

    private func loadComputes(request: UUID) async throws {
        guard let projectID, let branch else { return }
        let available = try await provider.computes(projectID: projectID, branch: branch)
        guard request == generation else { return }
        computes = available
    }

    private func begin() -> UUID {
        generation = UUID()
        isLoading = true
        lastError = nil
        return generation
    }
    private func finish(_ request: UUID) { if request == generation { isLoading = false } }
    private func fail(_ error: any Error, request: UUID) { if request == generation { lastError = error } }
    private func clearProjects() { projects = []; projectID = nil; clearBranches() }
    private func clearBranches() { branches = []; branch = nil; computes = [] }
}
