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
}
