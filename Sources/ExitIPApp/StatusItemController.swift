import AppKit
import ExitIPCore

/// Everything the menu needs to render, in one value.
struct MenuState {
    var model = ExitIPModel()
    var paused = false
    var interface: ActiveInterface?
    var latencyMs: Int?
    var latencyHistory: [Int?] = []
    var lastCheckedDate: Date?
    /// A check is in flight: the title spins and "last checked" reads "Checking…".
    var checking = false
    /// Set only while a captive portal is detected.
    var portalSignIn: PortalSignIn?
    var viaTunnel = false
    var history: [IPChangeEvent] = []
    var expectedCountryCode: String?
    var notificationsEnabled = Config.notificationsEnabledByDefault
    var loginEnabled = false
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var state = MenuState()
    /// Spins beside the title while a check is in flight; lives inside the
    /// status item's button, over the space an (empty) leading image reserves.
    private let spinner = SpinnerFactory.make()
    private static let spinnerSlot = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }

    var onRefresh: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onToggleNotifications: () -> Void = {}
    var onToggleLogin: () -> Void = {}
    var onSetExpectedCountry: (String?) -> Void = { _ in }
    var onClearHistory: () -> Void = {}
    var onOpenSignIn: (URL) -> Void = { _ in }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.addSubview(spinner)
        statusItem.button?.imagePosition = .imageLeading
        render()
    }

    func update(_ state: MenuState) {
        self.state = state
        render()
    }

    /// Shows or hides the title spinner. A blank 16 pt image reserves its slot
    /// so the title shifts right by exactly that much while it's visible.
    private func layoutSpinner() {
        guard let button = statusItem.button else { return }
        if state.checking {
            button.image = Self.spinnerSlot
            let slot = (button.cell as? NSButtonCell)?.imageRect(forBounds: button.bounds) ?? NSRect(x: 4, y: 3, width: 16, height: 16)
            spinner.frame = NSRect(x: slot.midX - 8, y: slot.midY - 8, width: 16, height: 16)
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            button.image = nil
        }
    }

    // Re-render on open so the time-based lines ("last checked", "unchanged for")
    // are current rather than as of the last poll.
    func menuWillOpen(_ menu: NSMenu) {
        populateMenu()
    }

    private func render() {
        statusItem.button?.title = menuBarTitle(for: state.model, paused: state.paused)
        layoutSpinner()
        populateMenu()
    }

    private func populateMenu() {
        menu.removeAllItems()
        let now = Date()

        if let snapshot = state.model.lastGood {
            menu.addItem(copyItem(ipLine(for: snapshot.primary), copies: snapshot.primary.ip))
            if let v6 = snapshot.ipv6 {
                menu.addItem(copyItem(ipv6Line(for: v6), copies: v6.ip))
            }
            if let loc = locationLine(for: snapshot.primary) { menu.addItem(disabledItem(loc)) }
            if let isp = ispLine(for: snapshot.primary) { menu.addItem(disabledItem(isp)) }
            if let dns = snapshot.dnsResolver { menu.addItem(copyItem(dnsLine(for: dns), copies: dns.ip)) }
        } else {
            menu.addItem(disabledItem("No IP yet"))
        }

        menu.addItem(disabledItem(interfaceLine(state.interface)))
        menu.addItem(disabledItem(latencyLine(ms: state.latencyMs, trend: state.latencyHistory)))
        if let last = state.history.last {
            let seconds = Int(now.timeIntervalSince(last.date))
            menu.addItem(disabledItem(stableForText(seconds: seconds)))
        }
        let checkedAgo = state.lastCheckedDate.map { Int(now.timeIntervalSince($0)) } ?? 0
        if state.checking {
            let item = disabledItem(checkingText)
            item.view = SpinnerMenuItemView(title: checkingText)
            menu.addItem(item)
        } else {
            menu.addItem(disabledItem(lastCheckedText(secondsAgo: checkedAgo)))
        }

        // Always offered: portal detection can miss (e.g. the portal only
        // intercepts some traffic), and macOS's own assistant only checks on join.
        let status = portalStatus(for: state.model, signIn: state.portalSignIn)
        let signInItem = actionItem(signInMenuTitle(status), #selector(openSignIn), key: "")
        signInItem.view = BadgedMenuItemView(title: signInItem.title, badge: signInBadge(status))
        menu.addItem(signInItem)
        if let signIn = state.portalSignIn, let hint = signInHint(signIn, viaTunnel: state.viaTunnel) {
            menu.addItem(disabledItem(hint))
        }

        let warnings = state.model.activeWarnings
        if let snapshot = state.model.lastGood, !warnings.isEmpty {
            menu.addItem(.separator())
            for warning in warnings {
                menu.addItem(disabledItem(warningLine(warning, snapshot: snapshot, expectedCountryCode: state.expectedCountryCode)))
            }
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Refresh now", #selector(refresh), key: "r"))

        let pause = actionItem("Pause monitoring", #selector(togglePause), key: "")
        pause.state = state.paused ? .on : .off
        menu.addItem(pause)

        let expected = NSMenuItem(title: "Expected exit", action: nil, keyEquivalent: "")
        expected.submenu = buildExpectedMenu()
        menu.addItem(expected)

        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        historyItem.submenu = buildHistoryMenu(now: now)
        menu.addItem(historyItem)

        let notif = actionItem("Notifications", #selector(toggleNotifications), key: "")
        notif.state = state.notificationsEnabled ? .on : .off
        menu.addItem(notif)

        let login = actionItem("Launch at login", #selector(toggleLogin), key: "")
        login.state = state.loginEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(actionItem("Quit", #selector(quit), key: "q"))
    }

    /// Off + every country the app has seen (current exit, pinned one, history),
    /// so pinning is one click while connected to the right place.
    private func buildExpectedMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        let selected = normalizedCountryCode(state.expectedCountryCode)
        let current = normalizedCountryCode(state.model.lastGoodIP?.countryCode)

        let off = actionItem("Off", #selector(setExpectedCountry), key: "")
        off.state = selected == nil ? .on : .off
        sub.addItem(off)

        let codes = expectedCountryChoices(current: current, pinned: selected, history: state.history)
        if !codes.isEmpty { sub.addItem(.separator()) }
        for code in codes {
            let title = code == current ? "\(countryLabel(code)) (current)" : countryLabel(code)
            let item = actionItem(title, #selector(setExpectedCountry), key: "")
            item.representedObject = code
            item.state = code == selected ? .on : .off
            sub.addItem(item)
        }
        return sub
    }

    private func buildHistoryMenu(now: Date) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        let events = state.history.suffix(Config.historyMenuLimit).reversed()
        if events.isEmpty {
            sub.addItem(disabledItem("No changes recorded"))
        }
        for event in events {
            let line = historyLine(event, timeText: historyTimeText(event.date, now: now))
            sub.addItem(copyItem(line, copies: event.to.ip))
        }
        sub.addItem(.separator())
        let clear = actionItem("Clear history", #selector(clearHistory), key: "")
        clear.isEnabled = !state.history.isEmpty
        sub.addItem(clear)
        return sub
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

    private func copyItem(_ title: String, copies text: String) -> NSMenuItem {
        let item = actionItem(title, #selector(copyRepresented(_:)), key: "")
        item.representedObject = text
        item.toolTip = "Click to copy"
        return item
    }

    @objc private func copyRepresented(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func setExpectedCountry(_ sender: NSMenuItem) {
        onSetExpectedCountry(sender.representedObject as? String)
    }

    @objc private func refresh() { onRefresh() }
    @objc private func togglePause() { onTogglePause() }
    @objc private func toggleNotifications() { onToggleNotifications() }
    @objc private func toggleLogin() { onToggleLogin() }
    @objc private func clearHistory() { onClearHistory() }
    @objc private func openSignIn() { onOpenSignIn(state.portalSignIn?.url ?? Config.captivePortalSignInURL) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
