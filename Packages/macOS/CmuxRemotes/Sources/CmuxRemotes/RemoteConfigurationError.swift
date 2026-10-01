/// Failures validating durable remote configuration.
public enum RemoteConfigurationError: Error, Equatable, Sendable {
    /// The requested default or mutation refers to an unknown profile.
    case missingProfile
    /// Another lifecycle operation already owns this profile.
    case operationInProgress
    /// A saved profile contains an empty identity or unsafe SSH destination.
    case invalidProfile
    /// Two saved entries have the same local identity.
    case duplicateIdentity
    /// The on-disk configuration was written by a newer unsupported schema.
    case unsupportedVersion
    /// A retry tried to replace the identity or runtime bundle of an existing operation.
    case operationIdentityChanged
    /// Editing a saved connection tried to retarget existing workspaces to another machine.
    case profileIdentityChanged
}
