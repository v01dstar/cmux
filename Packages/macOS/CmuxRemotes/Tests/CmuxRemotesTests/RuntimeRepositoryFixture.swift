import Foundation
@testable import CmuxRemotes

struct RuntimeRepositoryFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let probe = RuntimeTestProbe()
    let runner: ScriptedInstacloudRunner
    let service: RemoteRuntimeRepository
    init(revision: String = String(repeating: "a", count: 40)) {
        runner = ScriptedInstacloudRunner([.ok("{\"app\":\"cmux-tui\",\"build_identity\":\"\(revision)\",\"distribution_version\":\"0.1.0\",\"remote_protocol\":5,\"os\":\"macos\"}")])
        service = RemoteRuntimeRepository(commands: runner, probes: probe, client: URL(fileURLWithPath: "/test/cmux-tui"),
            directory: directory, sourceRepository: URL(string: "https://github.com/manaflow-ai/cmux.git")!, fileManager: FileManager())
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
