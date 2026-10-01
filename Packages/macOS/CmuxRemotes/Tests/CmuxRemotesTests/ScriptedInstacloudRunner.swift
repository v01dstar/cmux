import CmuxFoundation
import Foundation

actor ScriptedInstacloudRunner: CommandRunning {
    enum Response: Sendable { case ok(String), failure(String) }
    var calls: [[String]] = []
    private var responses: [Response]
    init(_ responses: [Response]) { self.responses = responses }
    func run(directory: String, executable: String, arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        calls.append(arguments)
        guard !responses.isEmpty else { return CommandResult(stdout: nil, stderr: "unexpected command", exitStatus: 1, timedOut: false, executionError: nil) }
        switch responses.removeFirst() {
        case .ok(let output): return CommandResult(stdout: output, stderr: nil, exitStatus: 0, timedOut: false, executionError: nil)
        case .failure(let message): return CommandResult(stdout: nil, stderr: message, exitStatus: 2, timedOut: false, executionError: nil)
        }
    }
}
