import Foundation

public enum Config {
    // Address lookups run every poll, so they use the cheapest endpoints available.
    public static let ipv4Providers: [IPProvider] = [
        IPProvider(name: "ipify", url: URL(string: "https://api.ipify.org?format=json")!, format: .ipifyJSON),
        IPProvider(name: "icanhazip", url: URL(string: "https://ipv4.icanhazip.com")!, format: .plainText),
    ]
    public static let ipv6Providers: [IPProvider] = [
        IPProvider(name: "ipify6", url: URL(string: "https://api6.ipify.org?format=json")!, format: .ipifyJSON, timeout: ipv6Timeout),
        IPProvider(name: "icanhazip6", url: URL(string: "https://ipv6.icanhazip.com")!, format: .plainText, timeout: ipv6Timeout),
    ]
    // Geo lookups only run when an address is first seen (results are cached per
    // address), which keeps well clear of the providers' unauthenticated rate limits.
    public static let geoProviders: [GeoProvider] = [
        GeoProvider(name: "ipinfo.io", format: .ipinfo, template: "https://ipinfo.io/{ip}/json"),
        GeoProvider(name: "ipwho.is", format: .ipwhois, template: "https://ipwho.is/{ip}"),
        GeoProvider(name: "ipapi.co", format: .ipapi, template: "https://ipapi.co/{ip}/json/"),
    ]
    public static let geoCacheLimit = 64

    public static let pollInterval: TimeInterval = 60
    public static let networkChangeDebounce: TimeInterval = 1.5
    public static let requestTimeout: TimeInterval = 10
    /// Hosts without IPv6 usually fail fast, but a broken IPv6 path can hang; keep it short.
    public static let ipv6Timeout: TimeInterval = 4
    public static let notificationsEnabledByDefault = true

    /// Lightweight connectivity probe (HTTP 204) for real reachability + latency.
    public static let probeURL = URL(string: "https://www.gstatic.com/generate_204")!
    /// Tried only when the HTTPS probe fails, to tell a captive portal from being
    /// offline: portals can intercept plain HTTP cleanly (they can't do that to TLS,
    /// which just fails), so a redirect or a foreign page here means a portal.
    /// Not used as the primary probe because some local filters block plain HTTP.
    public static let captiveProbeURL = URL(string: "http://www.gstatic.com/generate_204")!
    public static let probeExpectedStatus = 204
    public static let probeTimeout: TimeInterval = 5
    /// Opened from the menu when a captive portal is detected; any plain-HTTP page
    /// gets redirected to the portal's sign-in page.
    public static let captivePortalSignInURL = URL(string: "http://captive.apple.com/hotspot-detect.html")!

    /// Offline hysteresis: require this many consecutive failed checks before
    /// reporting offline; re-check this many seconds after a tentative failure.
    public static let offlineConfirmations = 2
    public static let offlineRecheckDelay: TimeInterval = 2

    /// DNS resolver check: a unique label under this zone forces a fresh lookup,
    /// and the endpoint reports which resolver asked for it. `{token}` is the
    /// label; the endpoint only answers for 32-hex (UUID-shaped) ones.
    public static let dnsProbeTemplate = "https://{token}.edns.ip-api.com/json"

    public static func dnsProbeURL(token: String) -> URL? {
        guard !token.isEmpty, token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return URL(string: dnsProbeTemplate.replacingOccurrences(of: "{token}", with: token.lowercased()))
    }

    public static func randomDNSToken() -> String {
        String((0..<32).map { _ in "0123456789abcdef".randomElement()! })
    }

    /// The resolver check takes several seconds (the endpoint waits for the
    /// query to arrive), so it runs on every Nth poll rather than every one.
    public static let dnsCheckEveryPolls = 5

    /// Latency samples kept for the trend sparkline in the menu.
    public static let latencyHistoryLimit = 12

    /// Exit-IP change history: entries kept on disk / shown in the menu.
    public static let historyLimit = 50
    public static let historyMenuLimit = 12
}
