import AppKit
import CmuxRemotes
import SwiftUI

extension AppDelegate {
    func savedRemoteNewWorkspaceMenu(context: MainWindowContext) -> NSMenuItem? {
        guard remotes != nil else { return nil }
        let parent = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        configureSavedRemoteNewWorkspaceMenu(parent, context: context, includesDefaultCommand: false)
        return parent
    }

    func configureSavedRemoteNewWorkspaceMenu(_ parent: NSMenuItem, context: MainWindowContext?, includesDefaultCommand: Bool) {
        guard let model = remotes?.locations else { return }
        let localName = String(localized: "menu.remotes.local", defaultValue: "Local")
        let format = String(localized: "menu.remotes.newWorkspace", defaultValue: "New Workspace — %@")
        let defaultName: String
        if !model.isLoaded { defaultName = String(localized: "menu.remotes.loading", defaultValue: "Loading…") }
        else if case .remote(let id) = model.configuration.defaultLocation {
            defaultName = model.configuration.profiles.first(where: { $0.id == id })?.name ?? localName
        } else { defaultName = localName }
        parent.title = String(format: format, defaultName)
        let menu = NSMenu()
        menu.autoenablesItems = false
        if includesDefaultCommand {
            let item = NSMenuItem(title: parent.title, action: #selector(openSavedRemoteMenuSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = RemoteLocationMenuSelection(location: nil, windowID: context?.windowId)
            let shortcut = KeyboardShortcutSettings.menuShortcut(for: .newTab)
            item.keyEquivalent = shortcut.menuItemKeyEquivalent ?? ""
            item.keyEquivalentModifierMask = shortcut.modifierFlags
            item.isEnabled = model.isLoaded
            menu.addItem(item)
            menu.addItem(.separator())
        }
        let choices: [(RemoteLocation, String)] = [(.local, localName)] + model.configuration.profiles.map { (.remote($0.id), $0.name) }
        for (location, name) in choices {
            let item = NSMenuItem(title: name, action: #selector(openSavedRemoteMenuSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = RemoteLocationMenuSelection(location: location, windowID: context?.windowId)
            item.isEnabled = model.isLoaded
            item.view = NSHostingView(rootView: RemoteLocationMenuRow(name: name, location: location, model: model,
                open: { [weak self, weak menu] in
                    menu?.cancelTracking()
                    self?.performNewWorkspaceAction(tabManager: context?.tabManager, debugSource: "menu.remoteLocation", location: location)
                }, setDefault: { [weak parent, weak menu] in
                    Task {
                        do {
                            try await model.setDefault(location)
                            parent?.title = String(format: format, name)
                            if includesDefaultCommand { menu?.items.first?.title = String(format: format, name) }
                        } catch { model.report(error) }
                    }
                }).disabled(!model.isLoaded))
            menu.addItem(item)
        }
        parent.submenu = menu
    }

    @objc func openSavedRemoteMenuSelection(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? RemoteLocationMenuSelection else { return }
        let context = mainWindowContexts.values.first(where: { $0.windowId == selection.windowID })
        guard selection.windowID == nil || context != nil else { return }
        performNewWorkspaceAction(tabManager: context?.tabManager, debugSource: "menu.remoteLocation.keyboard", location: selection.location)
    }
}
