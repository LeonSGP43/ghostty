import Cocoa
import SwiftUI

final class SSHConnectionsController: NSWindowController, NSWindowDelegate {
    private let store: AITerminalManagerStore

    init(store: AITerminalManagerStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.SSHConnections.windowTitle
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1280, height: 760)
        window.center()
        window.contentView = NSHostingView(
            rootView: SSHConnectionsView()
                .environmentObject(store)
        )

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for SSHConnectionsController")
    }

    func show() {
        store.refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
