import AppKit
import Testing
#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
struct RemoteLocationFileMenuPresenterTests {
    @Test func refreshesNativeRowsForTheMainMenuOnly() {
        let center = NotificationCenter()
        let root = NSMenu()
        let file = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let section = NSMenu()
        file.submenu = section
        root.addItem(file)
        let placeholder = NSMenuItem(title: "New Workspace", action: nil, keyEquivalent: "")
        placeholder.submenu = NSMenu()
        section.addItem(placeholder)
        var updates = 0
        let presenter = RemoteLocationFileMenuPresenter(center: center, mainMenu: { root }, placeholderTitle: "New Workspace") { item in
            updates += 1
            item.title = "New Workspace — machine-\(updates)"
            let native = NSMenu()
            let row = NSMenuItem(title: "Local", action: nil, keyEquivalent: "")
            row.view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 32))
            native.addItem(row)
            item.submenu = native
        }
        withExtendedLifetime(presenter) {
            center.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
            #expect(updates == 0)
            center.post(name: NSMenu.didBeginTrackingNotification, object: section)
            #expect(updates == 1)
            #expect(placeholder.submenu?.items.count == 1)
            #expect(placeholder.submenu?.items.first?.view != nil)
            // The marker must survive a changed default title and allow the next refresh.
            center.post(name: NSMenu.didBeginTrackingNotification, object: section)
            #expect(updates == 2)
            #expect(placeholder.title == "New Workspace — machine-2")
        }
    }

    @Test func releasesTrackingObserverWithPresenter() {
        let center = NotificationCenter()
        let root = NSMenu()
        weak var released: RemoteLocationFileMenuPresenter?
        do {
            let presenter = RemoteLocationFileMenuPresenter(center: center, mainMenu: { root }, placeholderTitle: "New Workspace") { _ in }
            released = presenter
            #expect(released != nil)
        }
        #expect(released == nil)
        center.post(name: NSMenu.didBeginTrackingNotification, object: root)
    }
}
