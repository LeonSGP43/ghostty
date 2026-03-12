import Cocoa
import SwiftUI
import GhosttyKit

final class AITerminalManagerController: TerminalController {
    private let store: AITerminalManagerStore
    private let theme = GhosttyChromeTheme()
    private var configObserver: NSObjectProtocol?
    private weak var referenceWindow: NSWindow?

    init(_ ghostty: Ghostty.App, store: AITerminalManagerStore) {
        self.store = store
        super.init(ghostty, withSurfaceTree: .init())

        configObserver = NotificationCenter.default.addObserver(
            forName: .ghosttyConfigDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncTheme()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for AITerminalManagerController")
    }

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let window else { return }

        titleOverride = L10n.AITerminalManager.windowTitle
        window.minSize = NSSize(width: 1240, height: 780)
        installContentView(force: true)
        syncTheme()
    }

    func show(tabbedInto parentWindow: NSWindow? = TerminalController.preferredParent?.window) {
        store.refresh()
        referenceWindow = parentWindow
        installContentView(force: false)
        syncTheme()

        guard let window else { return }

        if let parentWindow,
           parentWindow !== window {
            if parentWindow.isMiniaturized {
                parentWindow.deminiaturize(nil)
            }

            let sameTabGroup = SSHConnectionsController.windowsAreInSameTabGroup(window, parentWindow)
            if !sameTabGroup &&
                parentWindow.tabbingMode != .disallowed &&
                window.tabbingMode != .disallowed {
                _ = parentWindow.addTabbedWindowSafely(window, ordered: .above)
            }
        }

        relabelTabs()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func syncTheme() {
        let appDelegate = NSApp.delegate as? AppDelegate
        let backgroundColor = GhosttyChrome.resolvedBackgroundColor(
            appDelegate: appDelegate,
            referenceWindow: referenceWindow
        )
        theme.apply(backgroundColor: backgroundColor)

        window?.backgroundColor = backgroundColor
        if let referenceAppearance = referenceWindow?.appearance {
            window?.appearance = referenceAppearance
        } else if let appDelegate {
            window?.appearance = NSAppearance(ghosttyConfig: appDelegate.ghostty.config)
        }
    }

    private func installContentView(force: Bool) {
        guard let window else { return }
        if !force && window.contentView != nil {
            return
        }
        window.contentView = TerminalViewContainer {
            AITerminalManagerView()
                .environmentObject(store)
                .environmentObject(theme)
        }
    }
}
