import Foundation

public enum Config {
    public static let providers: [IPProvider] = [
        IPProvider(name: "ipinfo.io", url: URL(string: "https://ipinfo.io/json")!, kind: .ipinfo),
        IPProvider(name: "ipapi.co", url: URL(string: "https://ipapi.co/json/")!, kind: .ipapi),
        IPProvider(name: "ipify", url: URL(string: "https://api.ipify.org?format=json")!, kind: .ipify),
    ]
    public static let pollInterval: TimeInterval = 60
    public static let networkChangeDebounce: TimeInterval = 1.5
    public static let requestTimeout: TimeInterval = 10
    public static let notificationsEnabledByDefault = true

    /// Lightweight connectivity probe (HTTP 204) for real reachability + latency.
    public static let probeURL = URL(string: "https://www.gstatic.com/generate_204")!
    public static let probeTimeout: TimeInterval = 5

    /// Offline hysteresis: require this many consecutive failed checks before
    /// reporting offline; re-check this many seconds after a tentative failure.
    public static let offlineConfirmations = 2
    public static let offlineRecheckDelay: TimeInterval = 2
}
