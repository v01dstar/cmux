import Foundation

/// A named organization, project, or branch returned by the provider inventory.
public struct InstacloudResource: Decodable, Equatable, Identifiable, Sendable {
    /// Stable provider identifier.
    public let id: String
    /// Display name supplied by the provider.
    public let name: String
    /// Whether a branch is the project's default; absent on other resource kinds.
    public let isDefault: Bool?
    enum CodingKeys: String, CodingKey { case id, name; case isDefault = "is_default" }
}
