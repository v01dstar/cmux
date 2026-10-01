import CmuxRemotes
import SwiftUI

/// A location opens on label click; its separate checkbox changes only the default.
@MainActor
struct RemoteLocationMenuRow: View {
    let name: String
    let location: RemoteLocation
    let model: RemoteLocationsModel
    let open: @MainActor () -> Void
    let setDefault: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                Text(name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help(name)
            Toggle(String(localized: "menu.remotes.default", defaultValue: "Default"), isOn: Binding(
                get: { model.configuration.defaultLocation == location },
                set: { if $0 { setDefault() } }
            )).toggleStyle(.checkbox).fixedSize()
        }.padding(.horizontal, 12).padding(.vertical, 6).frame(width: 320)
    }
}
