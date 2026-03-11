import Cocoa
import SwiftUI

final class AITerminalManagerController: NSWindowController, NSWindowDelegate {
    private let store: AITerminalManagerStore

    init(store: AITerminalManagerStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.AITerminalManager.windowTitle
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: AITerminalManagerView()
                .environmentObject(store)
        )

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for AITerminalManagerController")
    }

    func show() {
        store.refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
