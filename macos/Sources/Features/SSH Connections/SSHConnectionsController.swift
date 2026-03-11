import Cocoa
import SwiftUI

final class SSHConnectionsController: NSWindowController, NSWindowDelegate {
    private let store: AITerminalManagerStore
    private let theme = GhosttyChromeTheme()
    private var configObserver: NSObjectProtocol?
    private weak var referenceWindow: NSWindow?

    static func windowsAreInSameTabGroup(_ lhs: NSWindow?, _ rhs: NSWindow?) -> Bool {
        guard
            let lhsGroup = lhs?.tabGroup,
            let rhsGroup = rhs?.tabGroup
        else { return false }

        return lhsGroup === rhsGroup
    }

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
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.tabbingMode = .preferred
        DispatchQueue.main.async {
            window.tabbingMode = .automatic
        }
        window.center()
        window.contentView = NSHostingView(
            rootView: SSHConnectionsView()
                .environmentObject(store)
                .environmentObject(theme)
        )

        super.init(window: window)
        window.delegate = self

        configObserver = NotificationCenter.default.addObserver(
            forName: .ghosttyConfigDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncChrome()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for SSHConnectionsController")
    }

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
    }

    func show(tabbedInto parentWindow: NSWindow? = TerminalController.preferredParent?.window) {
        store.refresh()
        referenceWindow = parentWindow
        syncChrome()

        if let window,
           let parentWindow,
           parentWindow !== window {
            if parentWindow.isMiniaturized {
                parentWindow.deminiaturize(nil)
            }

            let sameTabGroup = Self.windowsAreInSameTabGroup(window, parentWindow)
            if !sameTabGroup &&
                parentWindow.tabbingMode != .disallowed &&
                window.tabbingMode != .disallowed {
                _ = parentWindow.addTabbedWindowSafely(window, ordered: .above)
            }
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func syncChrome() {
        let appDelegate = NSApp.delegate as? AppDelegate
        let backgroundColor = GhosttyChrome.resolvedBackgroundColor(
            appDelegate: appDelegate,
            referenceWindow: referenceWindow
        )
        theme.apply(backgroundColor: backgroundColor)
        GhosttyChrome.syncWindowAppearance(
            window,
            appDelegate: appDelegate,
            referenceWindow: referenceWindow
        )
    }
}
