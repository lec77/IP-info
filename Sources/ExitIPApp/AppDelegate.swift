import AppKit
import ExitIPCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController!
    private let watcher = NetworkWatcher()
    private let resolver = ExitResolver.live()
    private let notifier = Notifier()
    private let probe = ConnectivityProbe()
    private let settings = SettingsStore()

    private var model = ExitIPModel()
    private var paused = false
    private var latencyMs: Int?
    private var lastCheckedDate: Date?
    private var pollTimer: Timer?
    private var debounceWorkItem: DispatchWorkItem?
    private var recheckWorkItem: DispatchWorkItem?
    private var isRefreshing = false
    private var failureStreak = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusItemController() // create the status item after the app finishes launching
        controller.onRefresh = { [weak self] in self?.refresh() }
        controller.onTogglePause = { [weak self] in self?.togglePause() }
        controller.onToggleNotifications = { [weak self] in self?.toggleNotifications() }
        controller.onToggleLogin = { [weak self] in self?.toggleLogin() }
        controller.onSetExpectedCountry = { [weak self] code in self?.setExpectedCountry(code) }
        controller.onClearHistory = { [weak self] in self?.clearHistory() }
        controller.onOpenSignIn = { NSWorkspace.shared.open(Config.captivePortalSignInURL) }

        if settings.notificationsEnabled { notifier.requestAuthorization() }

        watcher.onPathChange = { [weak self] online in
            MainActor.assumeIsolated { self?.handlePathChange(online: online) }
        }
        watcher.start()

        rerender()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Config.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    private func handlePathChange(online: Bool) {
        debounceWorkItem?.cancel()
        guard !paused else { return }
        guard online else {
            latencyMs = nil
            apply(outcome: .failure(.offline))
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.networkChangeDebounce, execute: work)
    }

    private func refresh() {
        guard !paused, !isRefreshing else { return }
        guard watcher.isOnline else { latencyMs = nil; apply(outcome: .failure(.offline)); return }
        isRefreshing = true
        let includeIPv6 = shouldLookupIPv6(pathSupportsIPv6: watcher.supportsIPv6, interface: watcher.interface)
        Task { @MainActor in
            let (verdict, latency) = await probe.check()
            self.latencyMs = latency
            let snapshot = (verdict == .reachable) ? await self.resolver.resolve(includeIPv6: includeIPv6) : nil
            NSLog("check: probe=\(verdict) latency=\(latency.map(String.init) ?? "-")ms exit=\(snapshot.map { "\($0.primary.ip) v6=\($0.ipv6?.ip ?? "-")" } ?? "none")")
            self.isRefreshing = false
            guard !self.paused else { return } // paused mid-flight: drop the result
            self.apply(outcome: combinedOutcome(probe: verdict, fetched: snapshot))
        }
    }

    private func apply(outcome: FetchOutcome) {
        let (report, streak) = confirmOutcome(outcome, failureStreak: failureStreak, confirmAfter: Config.offlineConfirmations)
        failureStreak = streak
        guard report else {
            // Tentative failure: keep the current display and re-check shortly to confirm.
            scheduleRecheck()
            return
        }
        if case .success(let snapshot) = outcome {
            lastCheckedDate = Date()
            settings.history = recordingExit(snapshot.primary, in: settings.history, at: Date())
            settings.homeExit = homeExit(after: snapshot, via: watcher.interface, previous: settings.homeExit)
        }
        let (newModel, notes) = reduce(model, applying: outcome, context: warningContext)
        model = newModel
        finish(posting: notes)
    }

    private var warningContext: WarningContext {
        WarningContext(
            expectedCountryCode: settings.expectedCountryCode,
            onTunnel: watcher.interface?.kind == .tunnel,
            homeExit: settings.homeExit
        )
    }

    private func finish(posting notes: [AppNotification]) {
        rerender()
        if settings.notificationsEnabled { notes.forEach(notifier.post) }
    }

    private func scheduleRecheck() {
        recheckWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        recheckWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.offlineRecheckDelay, execute: work)
    }

    private func rerender() {
        controller.update(MenuState(
            model: model,
            paused: paused,
            interface: watcher.interface,
            latencyMs: latencyMs,
            lastCheckedDate: lastCheckedDate,
            history: settings.history,
            expectedCountryCode: settings.expectedCountryCode,
            notificationsEnabled: settings.notificationsEnabled,
            loginEnabled: LoginItem.isEnabled
        ))
    }

    private func togglePause() {
        paused.toggle()
        if paused {
            debounceWorkItem?.cancel()
            recheckWorkItem?.cancel()
        }
        rerender()
        if !paused { refresh() }
    }

    private func setExpectedCountry(_ code: String?) {
        settings.expectedCountryCode = code
        let (newModel, notes) = reassess(model, context: warningContext)
        model = newModel
        finish(posting: notes)
    }

    private func clearHistory() {
        settings.history = []
        rerender()
    }

    private func toggleNotifications() {
        settings.notificationsEnabled.toggle()
        if settings.notificationsEnabled { notifier.requestAuthorization() }
        rerender()
    }

    private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        rerender()
    }
}
