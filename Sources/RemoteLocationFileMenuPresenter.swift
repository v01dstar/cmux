import AppKit

/// Replaces SwiftUI's flattened command contents with the shared native menu rows.
@MainActor
final class RemoteLocationFileMenuPresenter {
    private let center: NotificationCenter
    private let mainMenu: @MainActor () -> NSMenu?
    private let placeholderTitle: String
    private let configure: @MainActor (NSMenuItem) -> Void
    private let identifier = NSUserInterfaceItemIdentifier("cmux.savedRemoteLocations")
    // Assigned once during main-actor initialization; only exclusive deinit
    // reads it afterward. NotificationCenter permits removal on any thread.
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init(center: NotificationCenter, mainMenu: @escaping @MainActor () -> NSMenu?,
         placeholderTitle: String, configure: @escaping @MainActor (NSMenuItem) -> Void) {
        self.center = center
        self.mainMenu = mainMenu
        self.placeholderTitle = placeholderTitle
        self.configure = configure
        // Tracking must be updated synchronously before AppKit displays its menu;
        // an async notification stream would apply the projection after opening.
        observer = center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] notification in
            guard let menu = notification.object as? NSMenu else { return }
            var root = menu
            while let parent = root.supermenu { root = parent }
            let rootIdentity = ObjectIdentifier(root)
            MainActor.assumeIsolated {
                self?.prepare(trackedRootIdentity: rootIdentity)
            }
        }
    }

    private func prepare(trackedRootIdentity: ObjectIdentifier) {
        guard let root = mainMenu() else { return }
        guard ObjectIdentifier(root) == trackedRootIdentity else { return }
        for topLevel in root.items {
            guard let section = topLevel.submenu else { continue }
            guard let item = section.items.first(where: {
                $0.identifier == identifier || ($0.title == placeholderTitle && $0.submenu != nil)
            }) else { continue }
            item.identifier = identifier
            configure(item)
            return
        }
    }

    deinit {
        if let observer { center.removeObserver(observer) }
    }
}
