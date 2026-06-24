import AppKit
import ExitIPCore

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private var model = ExitIPModel()
    private var lastCheckedSecondsAgo = 0
    private var notificationsEnabled = Config.notificationsEnabledByDefault
    private var loginEnabled = false

    var onRefresh: () -> Void = {}
    var onToggleNotifications: () -> Void = {}
    var onToggleLogin: () -> Void = {}

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render()
    }

    func update(model: ExitIPModel, lastCheckedSecondsAgo: Int, notificationsEnabled: Bool, loginEnabled: Bool) {
        self.model = model
        self.lastCheckedSecondsAgo = lastCheckedSecondsAgo
        self.notificationsEnabled = notificationsEnabled
        self.loginEnabled = loginEnabled
        render()
    }

    private func render() {
        statusItem.button?.title = menuBarTitle(for: model)
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let info = model.lastGoodIP {
            let ipItem = NSMenuItem(title: ipLine(for: info), action: #selector(copyIP), keyEquivalent: "")
            ipItem.target = self
            menu.addItem(ipItem)
            if let loc = locationLine(for: info) { menu.addItem(disabledItem(loc)) }
            if let isp = ispLine(for: info) { menu.addItem(disabledItem(isp)) }
        } else {
            menu.addItem(disabledItem("No IP yet"))
        }

        menu.addItem(disabledItem(lastCheckedText(secondsAgo: lastCheckedSecondsAgo)))
        menu.addItem(.separator())

        menu.addItem(actionItem("Refresh now", #selector(refresh), key: "r"))

        let notif = actionItem("Notifications", #selector(toggleNotifications), key: "")
        notif.state = notificationsEnabled ? .on : .off
        menu.addItem(notif)

        let login = actionItem("Launch at login", #selector(toggleLogin), key: "")
        login.state = loginEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(actionItem("Quit", #selector(quit), key: "q"))
        return menu
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = true
        return item
    }

    @objc private func copyIP() {
        guard let ip = model.lastGoodIP?.ip else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
    }

    @objc private func refresh() { onRefresh() }
    @objc private func toggleNotifications() { onToggleNotifications() }
    @objc private func toggleLogin() { onToggleLogin() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
