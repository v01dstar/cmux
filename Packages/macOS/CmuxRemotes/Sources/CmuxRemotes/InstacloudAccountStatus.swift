/// The CLI's current login and project selection, without credential values.
public struct InstacloudAccountStatus: Decodable, Sendable {
    /// The signed-in user, absent when login is required.
    public let user: User?
    /// The CLI-linked project, used as a suggested selection only.
    public let project: Project?

    /// Minimal identity for display in the account picker.
    public struct User: Decodable, Sendable {
        /// Account email returned by the authenticated provider.
        public let email: String
    }
    /// Minimal linked-project context.
    public struct Project: Decodable, Sendable {
        /// Stable project ID.
        public let projectId: String
        /// Owning organization ID.
        public let orgId: String
        /// CLI-selected branch; new remotes still use the project's default branch.
        public let branch: String
    }
}
