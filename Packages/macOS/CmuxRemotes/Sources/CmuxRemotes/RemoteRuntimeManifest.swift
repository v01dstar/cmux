/// Image marker paired with the content-addressed deployment directory.
struct RemoteRuntimeManifest: Codable, Sendable {
    let kind: String
    let digest: String
    let binary: RemoteBinaryIdentity
}
