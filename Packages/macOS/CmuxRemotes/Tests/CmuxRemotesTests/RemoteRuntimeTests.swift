import Foundation
import Testing
@testable import CmuxRemotes

struct RemoteRuntimeTests {
    private var locator: InstacloudLocator {
        InstacloudLocator(organizationID: "org", projectID: "project", branch: "main", serviceID: "service", serviceName: "dev")
    }

    @Test func bundleIsContentAddressedPrivateAndReusable() async throws {
        let fixture = RuntimeRepositoryFixture()
        defer { fixture.cleanup() }
        let first = try await fixture.service.bundle(digest: nil)
        let reopened = try await fixture.service.bundle(digest: first.digest)
        #expect(first.digest.count == 64)
        #expect(reopened.directory == first.directory)
        #expect(await fixture.runner.calls.count == 1)
        let permissions = try FileManager.default.attributesOfItem(atPath: first.directory.path)[.posixPermissions] as? Int
        #expect(permissions == 0o700)
        let marker = try JSONDecoder().decode(RemoteRuntimeManifest.self, from: Data(contentsOf: first.directory.appendingPathComponent("runtime.json")))
        #expect(marker.digest == first.digest)
        #expect(marker.binary.buildIdentity == String(repeating: "a", count: 40))
    }

    @Test(arguments: ["edit", "extra", "symlink", "marker"])
    func alteredDeploymentInputsCannotResume(kind: String) async throws {
        let fixture = RuntimeRepositoryFixture()
        defer { fixture.cleanup() }
        let bundle = try await fixture.service.bundle(digest: nil)
        let path = bundle.directory.appendingPathComponent("health.py")
        switch kind {
        case "edit": try Data("changed".utf8).write(to: path)
        case "extra": try Data("unexpected".utf8).write(to: bundle.directory.appendingPathComponent("extra"))
        case "symlink":
            try FileManager.default.removeItem(at: path)
            try FileManager.default.createSymbolicLink(at: path, withDestinationURL: bundle.directory.appendingPathComponent("entrypoint.sh"))
        default: try Data("{}".utf8).write(to: bundle.directory.appendingPathComponent("runtime.json"))
        }
        await #expect(throws: InstacloudError.bundleChanged) { try await fixture.service.bundle(digest: bundle.digest) }
    }

    @Test func dirtySourceIdentityCannotBuildAnUnrelatedCleanRevision() async throws {
        let fixture = RuntimeRepositoryFixture(revision: String(repeating: "a", count: 40) + "-dirty")
        defer { fixture.cleanup() }
        await #expect(throws: InstacloudError.incompatibleRuntime) { try await fixture.service.bundle(digest: nil) }
    }

    @Test func runningCompatibleLinuxRuntimeIsAccepted() async throws {
        let fixture = RuntimeRepositoryFixture()
        defer { fixture.cleanup() }
        try await fixture.service.verifyMachine(locator, expectedDigest: String(repeating: "b", count: 64))
    }

    @Test(arguments: ["mount", "home", "binary", "ready", "digest"])
    func runtimeFactsMustAgreeBeforeConnecting(failure: String) async throws {
        let fixture = RuntimeRepositoryFixture()
        defer { fixture.cleanup() }
        await fixture.probe.configure(mounted: failure != "mount", home: failure == "home" ? "/root" : "/data/home",
            revision: failure == "binary" ? String(repeating: "c", count: 40) : nil, ready: failure != "ready")
        await #expect(throws: InstacloudError.incompatibleRuntime) {
            try await fixture.service.verifyMachine(locator, expectedDigest: failure == "digest" ? String(repeating: "c", count: 64) : nil)
        }
    }
}
