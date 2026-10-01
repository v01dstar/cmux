import CmuxFoundation
import Foundation

/// Runs bounded Instacloud commands using the caller's existing login and agent identity.
///
/// No shell strings are constructed. Project links live in isolated directories;
/// credentials and coding-agent environment variables are neither copied nor stripped.
public actor InstacloudCLI: InstacloudProviding {
    private let commands: any CommandRunning
    private let root: URL
    private let executable: String
    private let agentMode: Bool
    private let files: FileManager
    private var contexts: [String: Task<String, any Error>] = [:]

    /// Creates a provider client with injected command execution and private context storage.
    /// - Parameters:
    ///   - commands: Async bounded subprocess seam; tests supply scripted results.
    ///   - directory: Private parent for project-specific CLI working directories.
    ///   - executable: CLI name or absolute path.
    ///   - agentMode: Explicit agent flag for automation; the inherited environment remains intact in either mode.
    ///   - fileManager: Filesystem dependency, injectable for tests.
    public init(commands: any CommandRunning, directory: URL, executable: String = "insta",
                agentMode: Bool = false, fileManager: FileManager) {
        self.commands = commands
        self.root = directory
        self.executable = executable
        self.agentMode = agentMode
        self.files = fileManager
    }

    /// Reads current account identity without exposing tokens.
    public func account() async throws -> InstacloudAccountStatus {
        try prepareRoot()
        return try await json(["status", "--json"], directory: root.path)
    }

    /// Opens the provider's browser login flow; authentication is handled entirely by the CLI.
    public func login() async throws {
        try prepareRoot()
        _ = try await execute(["login"], directory: root.path, timeout: 300)
    }

    /// Lists organizations accessible to the logged-in user.
    public func organizations() async throws -> [InstacloudResource] {
        try prepareRoot()
        return try await json(["org", "list", "--json"], directory: root.path)
    }

    /// Lists projects in one explicitly selected organization.
    public func projects(organizationID: String) async throws -> [InstacloudResource] {
        try prepareRoot()
        return try await json(["project", "list", "--org", organizationID, "--json"], directory: root.path)
    }

    /// Lists the selected project's branches, including its provider-designated default.
    public func branches(projectID: String) async throws -> [InstacloudResource] {
        let directory = try await context(projectID)
        return try await json(["branch", "list", "--json"], directory: directory)
    }

    /// Lists compute services on the explicit branch, ignoring non-compute inventory rows.
    public func computes(projectID: String, branch: String) async throws -> [InstacloudCompute] {
        let directory = try await context(projectID)
        let services: [InstacloudCompute] = try await json(["service", "list", "--branch", branch, "--json"], directory: directory)
        return services.filter { $0.type == "compute" }
    }

    /// Checks both immutable identity and the persistent mount required by the runtime.
    public func verify(_ locator: InstacloudLocator, requireVolume: Bool = false) async throws -> InstacloudCompute {
        let inventory = try await computes(projectID: locator.projectID, branch: locator.branch)
        guard let service = inventory.first(where: { $0.name == locator.serviceName }) else {
            throw InstacloudError.missingCompute
        }
        guard service.id == locator.serviceID, service.projectID == locator.projectID else {
            throw InstacloudError.identityChanged
        }
        if requireVolume, (service.volumeGiB ?? 0) < 1 || service.volumeMountPath != "/data" {
            throw InstacloudError.missingVolume
        }
        return service
    }

    /// Fetches current state only after reconciling the saved resource identity.
    public func status(_ locator: InstacloudLocator) async throws -> InstacloudComputeStatus {
        _ = try await verify(locator)
        return try await statusAfterVerification(locator)
    }

    /// Issues exactly one lifecycle mutation; callers subsequently poll ``status(_:)``.
    public func setRunning(_ running: Bool, locator: InstacloudLocator) async throws {
        _ = try await verify(locator)
        let directory = try await context(locator.projectID)
        _ = try await execute(["compute", running ? "start" : "stop", locator.serviceName,
                               "--branch", locator.branch, "--json"], directory: directory)
    }

    /// Deletes the exact verified service and its provider resources; requires explicit UI confirmation.
    public func delete(_ locator: InstacloudLocator) async throws {
        _ = try await verify(locator)
        let directory = try await context(locator.projectID)
        _ = try await execute(["service", "remove", "compute", locator.serviceName,
                               "--branch", locator.branch, "--json"], directory: directory)
    }

    /// Creates a compute with a persistent volume using the journal's already-reserved name.
    public func create(_ operation: RemoteProvisioningOperation) async throws -> InstacloudCompute {
        let directory = try await context(operation.projectID)
        return try await json(["service", "add", "compute", operation.serviceName, "--branch", operation.branch,
                               "--volume", "10", "--mount-path", "/data", "--always-on", "--json"], directory: directory, timeout: 180)
    }

    /// Deploys the caller's verified runtime bundle to the exact saved compute.
    public func deploy(_ locator: InstacloudLocator, bundleDirectory: URL) async throws {
        _ = try await verify(locator, requireVolume: true)
        let directory = try await context(locator.projectID)
        _ = try await execute(["deploy", bundleDirectory.path, "--branch", locator.branch,
                               "--group", locator.serviceName, "--port", "8080", "--json"], directory: directory, timeout: 900)
    }

    /// Lets the CLI prepare its short-lived SSH certificate and managed alias.
    /// No returned certificate or private key is retained in a remote profile.
    public func prepareSSH(_ locator: InstacloudLocator) async throws -> String {
        _ = try await verify(locator, requireVolume: true)
        let directory = try await context(locator.projectID)
        _ = try await execute(["compute", "ssh", locator.serviceName, "--branch", locator.branch,
                               "--setup", "--json"], directory: directory, timeout: 90)
        return locator.serviceName + ".insta"
    }

    private func statusAfterVerification(_ locator: InstacloudLocator) async throws -> InstacloudComputeStatus {
        let directory = try await context(locator.projectID)
        return try await json(["compute", "status", locator.serviceName, "--branch", locator.branch, "--json"], directory: directory)
    }

    private func prepareRoot() throws {
        try files.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    private func context(_ projectID: String) async throws -> String {
        // UUID paths avoid path traversal from provider IDs. Project identities are checked by `project link`.
        guard UUID(uuidString: projectID) != nil else { throw InstacloudError.invalidResponse }
        if let task = contexts[projectID] { return try await task.value }
        try prepareRoot()
        let directory = root.appendingPathComponent(projectID, isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let task = Task { [self] in
            _ = try await execute(["project", "link", projectID, "--json"], directory: directory.path)
            return directory.path
        }
        contexts[projectID] = task
        do { return try await task.value }
        catch { contexts.removeValue(forKey: projectID); throw error }
    }

    private func json<Value: Decodable & Sendable>(_ arguments: [String], directory: String,
                                                  timeout: TimeInterval = 30) async throws -> Value {
        let output = try await execute(arguments, directory: directory, timeout: timeout)
        guard let data = output.data(using: .utf8), let value = try? JSONDecoder().decode(Value.self, from: data) else {
            throw InstacloudError.invalidResponse
        }
        return value
    }

    private func execute(_ arguments: [String], directory: String, timeout: TimeInterval = 30) async throws -> String {
        try Task.checkCancellation()
        let result = await commands.run(directory: directory, executable: executable,
                                        arguments: (agentMode ? ["--agent"] : []) + arguments, timeout: timeout)
        try Task.checkCancellation()
        if result.timedOut { throw InstacloudError.timedOut }
        if result.executionError != nil { throw InstacloudError.unavailable }
        guard result.exitStatus == 0 else {
            let diagnostic = (result.stderr ?? "") + (result.stdout ?? "")
            if diagnostic.localizedCaseInsensitiveContains("approval required") || diagnostic.contains("approval_required") {
                let pattern = #"(?:approve |approvalId[\" :]+)([a-zA-Z0-9-]{8,})"#
                let id = diagnostic.range(of: pattern, options: .regularExpression).flatMap {
                    diagnostic[$0].split(whereSeparator: { $0 == " " || $0 == "\"" || $0 == ":" }).last.map(String.init)
                }
                throw InstacloudError.approvalRequired(id)
            }
            if diagnostic.localizedCaseInsensitiveContains("not logged in") || diagnostic.contains("unauthenticated") {
                throw InstacloudError.loginRequired
            }
            throw InstacloudError.commandFailed(result.exitStatus)
        }
        return result.stdout ?? ""
    }
}
