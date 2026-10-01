import Foundation

/// Version information emitted by the local or remote cmux-tui binary itself.
public struct RemoteBinaryIdentity: Codable, Equatable, Sendable {
    /// Executable family, required to be cmux-tui.
    public let app: String
    /// Exact source identity used by SSH bootstrap compatibility checks.
    public let buildIdentity: String
    /// Distribution version used by SSH bootstrap compatibility checks.
    public let distributionVersion: String
    /// Remote protocol version supported by the executable.
    public let remoteProtocol: Int
    /// Operating system reported by the executable.
    public let os: String

    enum CodingKeys: String, CodingKey {
        case app, os
        case buildIdentity = "build_identity"
        case distributionVersion = "distribution_version"
        case remoteProtocol = "remote_protocol"
    }

    /// Checks the same version boundary as the cmux-tui SSH transport, allowing a different host OS.
    /// - Parameter other: The binary on the other end of the transport.
    /// - Returns: Whether both executables belong to the same compatible distribution.
    public func isCompatible(with other: Self) -> Bool {
        app == "cmux-tui" && other.app == app && buildIdentity == other.buildIdentity
            && distributionVersion == other.distributionVersion && remoteProtocol == other.remoteProtocol
    }
}
