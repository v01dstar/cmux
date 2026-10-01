import Foundation

/// Compute inventory used to verify immutable identity before every mutation.
public struct InstacloudCompute: Decodable, Equatable, Identifiable, Sendable {
    /// Immutable service identifier.
    public let id: String
    /// Current provider service name.
    public let name: String
    /// Service type; inventory can contain services other than compute.
    public let type: String
    /// Owning project; must match the selected profile.
    public let projectID: String
    /// Attached persistent volume size in GiB, if any.
    public let volumeGiB: Int?
    /// Requested persistent volume mount path.
    public let volumeMountPath: String?
    /// Deployed image, absent before the first deployment.
    public let image: String?
    enum CodingKeys: String, CodingKey {
        case id, name, type, image
        case projectID = "project_id"
        case volumeGiB = "volume_gib"
        case volumeMountPath = "volume_mount_path"
    }
}
