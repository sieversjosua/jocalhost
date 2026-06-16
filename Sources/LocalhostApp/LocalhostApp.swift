import AppKit
import Combine
import LocalhostCore
import SwiftUI

@main
struct LocalhostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ProjectStore()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var storeUpdates: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()

        storeUpdates = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusIcon()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.shutdown()
        popover?.close()
        statusItem = nil
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem

        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "jocalhost"
        updateStatusIcon()
    }

    private func configurePopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 480, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView()
                .environmentObject(store)
        )
        self.popover = popover
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        updateStatusIcon()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else {
            return
        }

        button.image = menuBarImage()
        button.imagePosition = .imageOnly
        button.contentTintColor = nil
    }

    private func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let text = NSAttributedString(
            string: "jo",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13.5, weight: .bold),
                .foregroundColor: NSColor.black,
                .kern: -1.3
            ]
        )
        let size = text.size()
        text.draw(at: NSPoint(x: (18 - size.width) / 2, y: (18 - size.height) / 2 - 0.5))

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "jocalhost"
        return image
    }
}
