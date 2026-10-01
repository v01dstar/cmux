import CmuxFoundation
import CryptoKit
import Foundation

/// Prepares immutable runtime bundles and verifies live machines against the actual local client.
public actor RemoteRuntimeRepository: RemoteRuntimeServicing {
    private let commands: any CommandRunning
    private let probes: any RemoteRuntimeProbing
    private let client: URL
    private let directory: URL
    private let sourceRepository: URL
    private let templates: URL?
    private let files: FileManager
    private var identity: RemoteBinaryIdentity?
    private let payloadNames = ["Dockerfile", "entrypoint.sh", "health.py", "install-zig.sh"]

    /// Creates a runtime service without reading files or executing commands during app initialization.
    /// - Parameters:
    ///   commands: Runs the local client's version probe.
    ///   probes: Reads runtime facts from an explicitly running compute.
    ///   client: The cmux-tui executable bundled with this app.
    ///   directory: Private content-addressed deployment cache.
    ///   sourceRepository: HTTPS GitHub source repository containing the client's exact commit.
    ///   fileManager: Filesystem dependency for bundle preparation and validation.
    ///   templateDirectory: Optional injected templates; defaults to the package's runtime resources.
    public init(commands: any CommandRunning, probes: any RemoteRuntimeProbing, client: URL,
                directory: URL, sourceRepository: URL, fileManager: FileManager,
                templateDirectory: URL? = nil) {
        self.commands = commands
        self.probes = probes
        self.client = client
        self.directory = directory
        self.sourceRepository = sourceRepository
        self.files = fileManager
        self.templates = templateDirectory ?? Bundle.module.url(forResource: "Runtime", withExtension: nil)
    }

    /// Loads the original journaled bundle or prepares the bundle matching this app's local client.
    /// - Parameter digest: An existing operation's immutable content digest, or nil for new setup.
    /// - Returns: A validated, private deployment directory.
    /// - Throws: Missing client, unsupported source identity, modified bundle, or filesystem errors.
    public func bundle(digest: String?) async throws -> RemoteRuntimeBundle {
        let binary = try await localIdentity()
        if let digest {
            guard validDigest(digest) else { throw InstacloudError.bundleChanged }
            let existing = RemoteRuntimeBundle(directory: directory.appendingPathComponent(digest, isDirectory: true), digest: digest)
            try await validate(existing)
            return existing
        }
        guard binary.buildIdentity.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              sourceRepository.absoluteString.range(of: "^https://github[.]com/[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+[.]git$", options: .regularExpression) != nil,
              let templates else { throw InstacloudError.incompatibleRuntime }
        var payload: [String: Data] = [:]
        for name in payloadNames {
            let templateName = name == "Dockerfile" ? "Dockerfile.template" : name
            var content = try String(contentsOf: templates.appendingPathComponent(templateName), encoding: .utf8)
            if name == "Dockerfile" {
                content = content.replacingOccurrences(of: "{{revision}}", with: binary.buildIdentity)
                    .replacingOccurrences(of: "{{repository}}", with: sourceRepository.absoluteString)
            }
            payload[name] = Data(content.utf8)
        }
        let digest = hash(payload)
        let result = RemoteRuntimeBundle(directory: directory.appendingPathComponent(digest, isDirectory: true), digest: digest)
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        if !files.fileExists(atPath: result.directory.path) {
            let staging = directory.appendingPathComponent(".preparing-" + UUID().uuidString)
            try files.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? files.removeItem(at: staging) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            payload["runtime.json"] = try encoder.encode(RemoteRuntimeManifest(kind: "cmux-instacloud-v1", digest: digest, binary: binary))
            for (name, contents) in payload {
                let path = staging.appendingPathComponent(name)
                try contents.write(to: path, options: .atomic)
                try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            }
            try files.moveItem(at: staging, to: result.directory)
        }
        try await validate(result)
        return result
    }

    /// Rehashes the complete payload and rejects changed files, extra files, symlinks, or version drift.
    /// - Parameter bundle: The immutable bundle reserved by a provisioning operation.
    /// - Throws: If any deployment input differs from its reserved identity.
    public func validate(_ bundle: RemoteRuntimeBundle) async throws {
        let binary = try await localIdentity()
        guard validDigest(bundle.digest),
              bundle.directory.standardizedFileURL == directory.appendingPathComponent(bundle.digest, isDirectory: true).standardizedFileURL else {
            throw InstacloudError.bundleChanged
        }
        do {
            let names = try files.contentsOfDirectory(atPath: bundle.directory.path)
            guard Set(names) == Set(payloadNames + ["runtime.json"]) else { throw InstacloudError.bundleChanged }
            var payload: [String: Data] = [:]
            for name in names {
                let path = bundle.directory.appendingPathComponent(name)
                let values = try path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw InstacloudError.bundleChanged }
                payload[name] = try Data(contentsOf: path)
            }
            guard let marker = payload.removeValue(forKey: "runtime.json") else { throw InstacloudError.bundleChanged }
            let manifest = try JSONDecoder().decode(RemoteRuntimeManifest.self, from: marker)
            guard hash(payload) == bundle.digest, manifest.digest == bundle.digest,
                  manifest.kind == "cmux-instacloud-v1", manifest.binary.isCompatible(with: binary) else {
                throw InstacloudError.bundleChanged
            }
        } catch { throw InstacloudError.bundleChanged }
    }

    /// Verifies real mount, persistent directories, boot readiness, and executable compatibility.
    /// - Parameters:
    ///   locator: Exact cloud machine identity.
    ///   expectedDigest: The creation journal's digest, or nil for a compatible existing machine.
    /// - Throws: Provider errors or incompatible runtime/storage facts.
    public func verifyMachine(_ locator: InstacloudLocator, expectedDigest: String?) async throws {
        let local = try await localIdentity()
        let remote = try await probes.inspectRuntime(locator)
        guard remote.kind == "cmux-instacloud-v1", validDigest(remote.digest),
              expectedDigest == nil || remote.digest == expectedDigest,
              remote.mounted, remote.ready, remote.home == "/data/home", remote.workspace == "/data/workspace",
              remote.binary.os == "linux", local.isCompatible(with: remote.binary) else {
            throw InstacloudError.incompatibleRuntime
        }
    }

    private func localIdentity() async throws -> RemoteBinaryIdentity {
        if let identity { return identity }
        let result = await commands.run(directory: client.deletingLastPathComponent().path, executable: client.path,
                                        arguments: ["remote-probe", "--json"], timeout: 20)
        try Task.checkCancellation()
        guard !result.timedOut, result.executionError == nil, result.exitStatus == 0,
              let data = result.stdout?.data(using: .utf8),
              let value = try? JSONDecoder().decode(RemoteBinaryIdentity.self, from: data), value.app == "cmux-tui" else {
            throw InstacloudError.incompatibleRuntime
        }
        identity = value
        return value
    }

    private func validDigest(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    private func hash(_ payload: [String: Data]) -> String {
        var hasher = SHA256()
        for name in payload.keys.sorted() {
            guard let data = payload[name] else { continue }
            hasher.update(data: Data("\(name.utf8.count):\(name):\(data.count):".utf8))
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
