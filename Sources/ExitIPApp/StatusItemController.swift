import AppKit
import Network
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
    var physicalInterface: ActiveInterface?
    var directInfo: IPInfo?
    var directCheckedDate: Date?
    var directFresh = false
    var history: [IPChangeEvent] = []
    var expectedCountryCode: String?
    var pollInterval = Config.pollInterval
    var notificationsEnabled = Config.notificationsEnabledByDefault
    var loginEnabled = false
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var state = MenuState()
    private let checkingMark = CheckingMark()

    var onRefresh: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onToggleNotifications: () -> Void = {}
    var onToggleLogin: () -> Void = {}
    var onSetExpectedCountry: (String?) -> Void = { _ in }
    var onClearHistory: () -> Void = {}
    var onSetPollInterval: (TimeInterval) -> Void = { _ in }
    var onOpenSignIn: (URL) -> Void = { _ in }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        render()
    }

    func update(_ state: MenuState) {
        self.state = state
        render()
    }

    // Re-render on open so the time-based lines ("last checked", "unchanged for")
    // are current rather than as of the last poll.
    func menuWillOpen(_ menu: NSMenu) {
        populateMenu()
    }

    private func render() {
        statusItem.button?.title = menuBarTitle(for: state.model, paused: state.paused)
        populateMenu()
    }

    private func populateMenu() {
        menu.removeAllItems()
        let now = Date()

        menu.addItem(sectionHeader(state.viaTunnel ? "VPN TUNNEL" : "CURRENT EXIT"))
        menu.addItem(disabledItem(interfaceLine(state.interface).replacingOccurrences(of: "Via: ", with: "")))
        if let snapshot = state.model.lastGood {
            addExitDetails(snapshot.primary)
            if let v6 = snapshot.ipv6 { menu.addItem(addressItem(v6)) }
            if state.model.phase != .ok { menu.addItem(disabledItem("Showing last successful reading")) }
        } else {
            menu.addItem(disabledItem(state.checking ? "Looking up exit…" : "Exit unavailable"))
        }
        menu.addItem(disabledItem(latencyLine(ms: state.latencyMs, trend: state.latencyHistory)))

        if state.viaTunnel {
            menu.addItem(.separator())
            menu.addItem(sectionHeader("DIRECT"))
            menu.addItem(disabledItem(interfaceLine(state.physicalInterface).replacingOccurrences(of: "Via: ", with: "")))
            if let direct = state.directInfo {
                addExitDetails(direct)
                if !state.directFresh, let checked = state.directCheckedDate {
                    let age = durationText(seconds: Int(now.timeIntervalSince(checked)))
                    let label = "Stale · Last success \(age) ago"
                    menu.addItem(disabledItem(label))
                }
            } else {
                menu.addItem(disabledItem(state.checking ? "Measuring direct exit…" : "Direct exit unavailable"))
            }
        }

        menu.addItem(.separator())
        menu.addItem(sectionHeader("CONNECTION CHECK"))
        let comparison = exitComparisonText(model: state.model, onTunnel: state.viaTunnel,
                                           direct: state.directFresh ? state.directInfo : nil)
        let summary = readableItem(comparison)
        summary.toolTip = "Compares the detected exit with a fresh direct measurement of the same IP family. Routing rules may intentionally send a request directly. This is not a VPN-wide leak test."
        menu.addItem(summary)
        if let snapshot = state.model.lastGood {
            for warning in state.model.activeWarnings where warning != .tunnelExitIsDirect {
                let title: String
                switch warning {
                case .unexpectedCountry: title = "⚠ Exit country differs from expected"
                case .ipv6Mismatch: title = "⚠ IPv6 exit differs from IPv4"
                case .dnsLeak: title = "⚠ DNS country differs from exit"
                case .tunnelExitIsDirect: continue
                }
                let item = readableItem(title)
                item.toolTip = warningLine(warning, snapshot: snapshot, expectedCountryCode: state.expectedCountryCode)
                menu.addItem(item)
            }
            if let dns = snapshot.dnsResolver {
                let item = copyItem(dnsLine(for: dns), copies: dns.ip)
                item.toolTip = "Resolver from the latest DNS check: \(dns.ip). Click to copy."
                menu.addItem(item)
            }
        }
        if state.checking {
            let item = disabledItem("Checking…")
            checkingMark.start(on: item)
            menu.addItem(item)
        } else {
            checkingMark.stop()
            let text = state.lastCheckedDate.map { lastCheckedText(secondsAgo: Int(now.timeIntervalSince($0))) } ?? "Not checked yet"
            menu.addItem(disabledItem(state.paused ? "Monitoring paused" : text))
        }
        if let last = state.history.last {
            menu.addItem(disabledItem(stableForText(seconds: Int(now.timeIntervalSince(last.date)))))
        }
        menu.addItem(actionItem("Refresh now", #selector(refresh), key: "r"))
        if case .failed(.captivePortal) = state.model.phase {
            menu.addItem(actionItem("Open network sign-in…", #selector(openSignIn), key: ""))
        }
        menu.addItem(.separator())
        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        historyItem.submenu = buildHistoryMenu(now: now)
        menu.addItem(historyItem)
        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settings.submenu = buildSettingsMenu()
        menu.addItem(settings)
        menu.addItem(actionItem("Quit IP-info", #selector(quit), key: "q"))
    }

    private func addExitDetails(_ info: IPInfo) {
        let country = info.countryCode.map(countryLabel) ?? info.countryName ?? "Location unavailable"
        let place = [country, info.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        menu.addItem(readableItem(place, weight: .semibold))
        menu.addItem(readableItem(info.isp ?? "ISP unavailable"))
        menu.addItem(addressItem(info))
    }

    private func addressItem(_ info: IPInfo) -> NSMenuItem {
        let family = IPv6Address(info.ip) == nil ? "IPv4" : "IPv6"
        let item = copyItem("\(family)  \(info.ip)", copies: info.ip)
        item.attributedTitle = NSAttributedString(string: item.title, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        ])
        return item
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = disabledItem(title)
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        return item
    }

    private func readableItem(_ title: String, weight: NSFont.Weight = .regular) -> NSMenuItem {
        let item = disabledItem(title)
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: weight),
            .foregroundColor: NSColor.labelColor
        ])
        return item
    }

    private func buildSettingsMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        let pause = actionItem(state.paused ? "Resume monitoring" : "Pause monitoring", #selector(togglePause), key: "")
        sub.addItem(pause)
        let expected = NSMenuItem(title: "Expected exit", action: nil, keyEquivalent: "")
        expected.submenu = buildExpectedMenu()
        sub.addItem(expected)
        let interval = NSMenuItem(title: "Check every", action: nil, keyEquivalent: "")
        interval.submenu = buildIntervalMenu()
        sub.addItem(interval)
        let notif = actionItem("Notifications", #selector(toggleNotifications), key: "")
        notif.state = state.notificationsEnabled ? .on : .off
        sub.addItem(notif)
        let login = actionItem("Launch at login", #selector(toggleLogin), key: "")
        login.state = state.loginEnabled ? .on : .off
        sub.addItem(login)
        sub.addItem(.separator())
        let status = portalStatus(for: state.model, signIn: state.portalSignIn)
        let signIn = actionItem("Open network sign-in…", #selector(openSignIn), key: "")
        signIn.toolTip = signInBadge(status)
        sub.addItem(signIn)
        if let portal = state.portalSignIn, let hint = signInHint(portal, viaTunnel: state.viaTunnel) {
            sub.addItem(disabledItem(hint))
        }
        return sub
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

    private func buildIntervalMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        for seconds in Config.pollIntervalChoices {
            let item = actionItem(pollIntervalLabel(seconds), #selector(setPollInterval), key: "")
            item.representedObject = seconds
            item.state = seconds == state.pollInterval ? .on : .off
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

    @objc private func setPollInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        onSetPollInterval(seconds)
    }

    @objc private func refresh() { onRefresh() }
    @objc private func togglePause() { onTogglePause() }
    @objc private func toggleNotifications() { onToggleNotifications() }
    @objc private func toggleLogin() { onToggleLogin() }
    @objc private func clearHistory() { onClearHistory() }
    @objc private func openSignIn() { onOpenSignIn(state.portalSignIn?.url ?? Config.captivePortalSignInURL) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
