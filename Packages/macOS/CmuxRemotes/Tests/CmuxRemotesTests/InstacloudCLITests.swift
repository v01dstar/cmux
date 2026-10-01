import CmuxFoundation
import Foundation
import Testing
@testable import CmuxRemotes

struct InstacloudCLITests {
    private let project = "7749cbb7-5849-45ee-8187-c0c08caa5edb"
    private var locator: InstacloudLocator {
        InstacloudLocator(organizationID: "org", projectID: project, branch: "test", serviceID: "original", serviceName: "dev")
    }
    private func service(_ id: String = "original", volume: Int = 10) -> String {
        #"[{"id":""# + id + #"","name":"dev","type":"compute","project_id":""# + project + #"","volume_gib": "# + String(volume) + #", "volume_mount_path":"/data"}]"#
    }

    @Test func replacedServiceCannotBeStopped() async throws {
        let runner = ScriptedInstacloudRunner([.ok("{}"), .ok(service("replacement"))])
        let cli = client(runner)
        await #expect(throws: InstacloudError.identityChanged) { try await cli.setRunning(false, locator: locator) }
        let calls = await runner.calls
        #expect(!calls.contains { $0.contains("stop") })
    }

    @Test func stopUsesPinnedBranchAndOneMutation() async throws {
        let runner = ScriptedInstacloudRunner([.ok("{}"), .ok(service()), .ok("{}")])
        try await client(runner).setRunning(false, locator: locator)
        let calls = await runner.calls
        #expect(calls.last == ["--agent", "compute", "stop", "dev", "--branch", "test", "--json"])
        #expect(calls.filter { $0.contains("stop") }.count == 1)
    }

    @Test func suspendedIsNotAlwaysStopped() throws {
        let stopped = try JSONDecoder().decode(InstacloudComputeStatus.self, from: Data(#"{"state":"suspended","desiredState":"stopped"}"#.utf8))
        let waking = try JSONDecoder().decode(InstacloudComputeStatus.self, from: Data(#"{"state":"suspended","desiredState":"running"}"#.utf8))
        #expect(stopped.isStopped)
        #expect(!waking.isStopped)
        #expect(!waking.isRunning)
    }

    @Test func sshSetupRejectsComputeWithoutPersistentVolume() async throws {
        let runner = ScriptedInstacloudRunner([.ok("{}"), .ok(service(volume: 0))])
        await #expect(throws: InstacloudError.missingVolume) { try await client(runner).prepareSSH(locator) }
        let calls = await runner.calls
        #expect(!calls.contains { $0.contains("ssh") })
    }

    @Test func approvalIsSurfacedWithoutRetry() async throws {
        let runner = ScriptedInstacloudRunner([.failure("approval required: insta agent approvals approve 12345678-abcd")])
        await #expect(throws: InstacloudError.approvalRequired("12345678-abcd")) { try await client(runner).organizations() }
        #expect(await runner.calls.count == 1)
    }

    @Test func malformedInventoryNeverAuthorizesDelete() async throws {
        let runner = ScriptedInstacloudRunner([.ok("{}"), .ok("not json")])
        await #expect(throws: InstacloudError.invalidResponse) { try await client(runner).delete(locator) }
        #expect(await runner.calls.count == 2)
    }

    private func client(_ runner: ScriptedInstacloudRunner) -> InstacloudCLI {
        InstacloudCLI(commands: runner, directory: FileManager.default.temporaryDirectory.appendingPathComponent("cmux-provider-tests/\(UUID())"), agentMode: true, fileManager: FileManager())
    }
}
