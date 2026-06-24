import AppKit
import ExitIPCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController!
    private let watcher = NetworkWatcher()
    private let fetcher: IPInfoFetching = URLSessionIPInfoFetcher()
    private let notifier = Notifier()

    private var model = ExitIPModel()
    private var notificationsEnabled = Config.notificationsEnabledByDefault
    private var lastCheckedDate: Date?
    private var pollTimer: Timer?
    private var debounceWorkItem: DispatchWorkItem?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusItemController() // create the status item after the app finishes launching
        controller.onRefresh = { [weak self] in self?.refresh() }
        controller.onToggleNotifications = { [weak self] in self?.toggleNotifications() }
        controller.onToggleLogin = { [weak self] in self?.toggleLogin() }

        notifier.requestAuthorization()

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
        guard online else {
            apply(outcome: .offline)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.networkChangeDebounce, execute: work)
    }

    private func refresh() {
        guard !isRefreshing else { return }
        guard watcher.isOnline else { apply(outcome: .offline); return }
        isRefreshing = true
        Task { @MainActor in
            let info = await fetcher.fetch()
            self.isRefreshing = false
            self.apply(outcome: info.map { .success($0) } ?? .lookupFailed)
        }
    }

    private func apply(outcome: FetchOutcome) {
        let (newModel, note) = reduce(model, applying: outcome)
        model = newModel
        if case .success = outcome { lastCheckedDate = Date() }
        rerender()
        if let note, notificationsEnabled { notifier.post(note) }
    }

    private func rerender() {
        let secondsAgo = lastCheckedDate.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
        controller.update(
            model: model,
            lastCheckedSecondsAgo: secondsAgo,
            notificationsEnabled: notificationsEnabled,
            loginEnabled: LoginItem.isEnabled
        )
    }

    private func toggleNotifications() {
        notificationsEnabled.toggle()
        if notificationsEnabled { notifier.requestAuthorization() }
        rerender()
    }

    private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        rerender()
    }
}
