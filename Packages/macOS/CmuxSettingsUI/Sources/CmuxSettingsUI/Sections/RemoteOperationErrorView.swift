import CmuxRemotes
import SwiftUI

/// Presents actionable failures without displaying raw command output or credentials.
struct RemoteOperationErrorView: View {
    let error: any Error
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(message, systemImage: "exclamationmark.triangle")
            if case .approvalRequired(let requestID)? = error as? InstacloudError,
               let requestID {
                Text(requestID).font(.caption.monospaced())
            }
        }.font(.callout).foregroundStyle(.red).textSelection(.enabled)
    }
    private var message: String {
        switch error as? InstacloudError {
        case .loginRequired:
            return String(localized: "settings.remotes.error.login", defaultValue: "Sign in to Instacloud, then try again.")
        case .sshAuthenticationRequired(let destination):
            return String(format: String(localized: "settings.remotes.error.sshAuthentication", defaultValue: "SSH sign-in is required for %@. Authenticate in a local terminal, then try opening this workspace again."), destination)
        case .approvalRequired:
            return String(localized: "settings.remotes.error.approval", defaultValue: "Instacloud requires your approval. Approve the original request in Instacloud, then resume setup here.")
        case .missingVolume, .incompatibleRuntime:
            return String(localized: "settings.remotes.error.runtime", defaultValue: "This machine needs a compatible cmux runtime and persistent storage. Its existing deployment has not been replaced.")
        case .identityChanged, .missingCompute:
            return String(localized: "settings.remotes.error.identity", defaultValue: "The saved machine was removed or replaced. Remove this connection and add the intended machine again.")
        case .machineNotRunning:
            return String(localized: "settings.remotes.error.notRunning", defaultValue: "The machine is not running yet. Refresh its status and try again.")
        case .creationUncertain, .timedOut, .transitionTimedOut:
            return String(localized: "settings.remotes.error.uncertain", defaultValue: "The operation has not been confirmed. Refresh status or resume the saved setup; do not create a replacement machine.")
        case .unavailable:
            return String(localized: "settings.remotes.error.cli", defaultValue: "Instacloud CLI is unavailable. Install insta and make it available to cmux, then try again.")
        default:
            return String(localized: "settings.remotes.error.generic", defaultValue: "The remote operation failed. Check the connection details and account access, then try again.")
        }
    }
}
