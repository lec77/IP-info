import Foundation

/// Where to send the user to sign in to a captive portal.
public struct PortalSignIn: Sendable, Equatable {
    public var url: URL
    /// The page lives on a LAN address. Those stay reachable even while a
    /// VPN/proxy tunnel is capturing everything else, so no tunnel-off hint.
    public var isLocal: Bool

    public init(url: URL, isLocal: Bool) {
        self.url = url
        self.isLocal = isLocal
    }
}

/// The page a portal bounced the probe to: the redirect's Location, resolved
/// against the probe URL since some portals send a relative one. Only a 3xx
/// with an http(s) Location counts; a portal that serves its own page in
/// place of the probe (2xx) gives no address to open.
public func portalRedirectURL(from head: HTTPResponseHead, requestURL: URL) -> URL? {
    guard (300...399).contains(head.statusCode),
          let location = head.header("location")?.trimmingCharacters(in: .whitespaces), !location.isEmpty,
          let url = URL(string: location, relativeTo: requestURL)?.absoluteURL,
          let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
          let host = url.host, !host.isEmpty
    else { return nil }
    return url
}

/// The sign-in target: the portal's own redirect when the probe caught one,
/// otherwise a plain-HTTP page any portal will intercept.
public func portalSignIn(redirect: URL?, fallback: URL = Config.captivePortalSignInURL) -> PortalSignIn {
    let url = redirect ?? fallback
    return PortalSignIn(url: url, isLocal: isLocalHost(url.host ?? ""))
}

/// Private / link-local / loopback addresses and LAN-only names.
public func isLocalHost(_ host: String) -> Bool {
    let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    guard !host.isEmpty else { return false }
    if host == "localhost" { return true }
    if let v4 = ipv4Octets(host) {
        switch (v4[0], v4[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }
    if host.contains(":") {
        return host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd")
    }
    if !host.contains(".") { return true } // single-label name: only resolvable on the LAN
    return [".local", ".lan", ".home", ".internal", ".localdomain", ".home.arpa"].contains { host.hasSuffix($0) }
}

private func ipv4Octets(_ host: String) -> [Int]? {
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return nil }
    let octets = parts.compactMap { Int($0) }.filter { (0...255).contains($0) }
    return octets.count == 4 ? octets : nil
}

/// What the last check said about a captive portal, for the sign-in item.
public enum PortalStatus: Sendable, Equatable {
    /// A portal intercepted the probe; `host` is where it redirected to, if known.
    case signInRequired(host: String?)
    /// The probe got through, so nothing is asking for a login.
    case notDetected
    /// Nothing to go on: no check yet, or no connectivity at all.
    case unknown
}

public func portalStatus(for model: ExitIPModel, signIn: PortalSignIn?) -> PortalStatus {
    switch model.phase {
    case .failed(.captivePortal): return .signInRequired(host: signIn?.url.host)
    case .ok, .failed(.lookupFailed): return .notDetected
    case .initial, .failed(.offline): return .unknown
    }
}

/// Menu item title for opening the sign-in page. The item is always offered
/// (detection can miss), so the title carries whether a login is actually
/// being asked for, and names the portal's host when the probe caught it.
public func signInMenuTitle(_ status: PortalStatus) -> String {
    switch status {
    case .signInRequired(let host?) where !host.isEmpty: return "⚠︎ Sign-in required — open portal page (\(host))…"
    case .signInRequired: return "⚠︎ Sign-in required — open portal page…"
    case .notDetected: return "Open sign-in page (no portal detected)…"
    case .unknown: return "Open sign-in page…"
    }
}

/// A line to show under the sign-in item when the page probably won't load:
/// a VPN/proxy tunnel is carrying the default route, so the browser's request
/// goes into the tunnel instead of reaching the portal. LAN addresses are the
/// exception (tunnels leave those alone).
public func signInHint(_ signIn: PortalSignIn, viaTunnel: Bool) -> String? {
    guard viaTunnel, !signIn.isLocal else { return nil }
    return "⚠︎ Turn off the VPN/proxy tunnel first, or the page won't load"
}
