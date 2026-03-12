import AppKit

extension AppDelegate {
    @IBAction func showAITerminalManager(_ sender: Any?) {
        aiTerminalManagerController.show(tabbedInto: TerminalController.preferredParent?.window)
    }
}
