import CmuxRemotes
import Foundation

/// Retains the immutable menu choice for AppKit's keyboard activation path.
final class RemoteLocationMenuSelection: NSObject {
    let location: RemoteLocation?
    let windowID: UUID?
    init(location: RemoteLocation?, windowID: UUID?) {
        self.location = location
        self.windowID = windowID
    }
}
