import Foundation
@testable import CmuxRemotes

actor ProvisioningTestRuntime: RemoteRuntimeServicing {
    var changed = false
    var incompatible = false
    var verifications = 0
    func changeBundle() { changed = true }
    func rejectRuntime() { incompatible = true }
    func bundle(digest: String?) -> RemoteRuntimeBundle {
        RemoteRuntimeBundle(directory: URL(fileURLWithPath: "/unused-test-bundle"), digest: "original-digest")
    }
    func validate(_ bundle: RemoteRuntimeBundle) throws {
        if changed { throw InstacloudError.bundleChanged }
    }
    func verifyMachine(_ locator: InstacloudLocator, expectedDigest: String?) throws {
        verifications += 1
        if incompatible { throw InstacloudError.incompatibleRuntime }
    }
}
