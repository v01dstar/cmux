import Foundation
@testable import CmuxRemotes

actor RuntimeTestProbe: RemoteRuntimeProbing {
    var mounted = true
    var home = "/data/home"
    var revision = String(repeating: "a", count: 40)
    var ready = true
    func configure(mounted: Bool = true, home: String = "/data/home", revision: String? = nil, ready: Bool = true) {
        self.mounted = mounted; self.home = home; self.ready = ready
        if let revision { self.revision = revision }
    }
    func inspectRuntime(_ locator: InstacloudLocator) throws -> RemoteRuntimeInspection {
        let data = try JSONSerialization.data(withJSONObject: [
            "kind": "cmux-instacloud-v1", "digest": String(repeating: "b", count: 64),
            "mounted": mounted, "home": home, "workspace": "/data/workspace", "ready": ready,
            "binary": ["app": "cmux-tui", "build_identity": revision, "distribution_version": "0.1.0", "remote_protocol": 5, "os": "linux"],
        ])
        return try JSONDecoder().decode(RemoteRuntimeInspection.self, from: data)
    }
}
