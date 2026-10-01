# CmuxRemotes

Saved workspace destinations and Instacloud machine lifecycle for the macOS app.
The package has no AppKit dependency. `RemotesComposition` in the app constructs
the services once; menus, shortcuts, and Settings share the resulting models.

- `RemoteConfigurationRepository` persists profiles, the default destination,
  reconnect intent, and provisioning journals atomically. Its snapshots have
  monotonically increasing revisions.
- `RemoteWorkspaceCoordinator` resolves an explicit destination or the saved
  default. Failure never falls back to Local. Restore checks reconnect intent
  and current machine state without starting a stopped machine.
- `RemoteLocationsModel` serializes connection and lifecycle operations per
  profile. Stop persists reconnect-disabled state and detaches transports before
  sending the provider mutation.
- `RemoteProvisioningCoordinator` records stable creation inputs before making
  requests. Resume reconciles uncertain outcomes instead of creating another
  machine or repeating deployment. Adding an existing machine verifies its
  volume and runtime without redeploying it.
- `InstacloudCLI` invokes the CLI with argument arrays and verifies immutable
  machine identity before mutation. Agent approval errors remain visible to the
  caller; the service never approves its own requests.
- `RemoteRuntimeRepository` prepares content-addressed Linux runtime bundles and
  checks the mounted persistent volume, actual executable identity, and runtime
  marker before connecting.

Removing a profile only removes local metadata. Deleting a compute is a separate
provider operation. Removing the default profile resets the default to Local.

## Testing

Run from the repository root:

```sh
swift test --package-path Packages/macOS/CmuxRemotes
```

Tests inject storage paths, provider/runtime implementations, and status timing.
They do not launch the app or require an Instacloud account. For example, the
workspace routing tests construct the model with an isolated repository and a
scripted provider:

```swift
let repository = RemoteConfigurationRepository(
    fileURL: temporaryDirectory.appendingPathComponent("remotes.json"),
    fileManager: FileManager()
)
let locations = RemoteLocationsModel(
    repository: repository,
    provider: scriptedProvider,
    beforeStop: { profileID in await transportSpy.detach(profileID) }
)
let workspaces = RemoteWorkspaceCoordinator(
    locations: locations,
    runtime: scriptedRuntime
)
```

See [RemoteLifecycleFixture](Tests/CmuxRemotesTests/RemoteLifecycleFixture.swift)
and [routing tests](Tests/CmuxRemotesTests/RemoteWorkspaceCoordinatorTests.swift)
for runnable fixtures and assertions covering default selection, cancelled
starts, failed runtime checks, and disabled reconnect.

Package tests establish domain behavior. Native menu interaction, SSH transport,
remote pane placement, browser routing, and process persistence require separate
tagged-app integration checks.
