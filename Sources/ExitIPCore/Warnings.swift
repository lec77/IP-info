import Network

/// Things that are wrong with an otherwise successful reading — the exit is not
/// where it should be. Distinct from connectivity failures (`FailureReason`).
/// Cases carry no payload: everything they describe is derivable from the
/// snapshot and context they were assessed against, and the one comparison
/// that matters (did a warning appear / clear) is by case.
public enum ExitWarning: Sendable, Hashable {
    /// The primary exit's country differs from the pinned expectation.
    case unexpectedCountry
    /// IPv6 traffic exits somewhere other than IPv4 does — the classic VPN leak.
    case ipv6Mismatch
    /// A tunnel is active but the primary exit matches a fresh, interface-bound
    /// direct measurement. Split routing can intentionally produce this result.
    case tunnelExitIsDirect
    /// DNS queries are answered by a resolver in a different country than the
    /// exit — name lookups are bypassing the tunnel.
    case dnsLeak

    public enum Severity: Int, Sendable, Comparable {
        case caution, critical

        public var glyph: String {
            switch self {
            case .caution: return "⚠︎"
            case .critical: return "⛔"
            }
        }

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var severity: Severity {
        switch self {
        case .unexpectedCountry: return .critical
        case .ipv6Mismatch, .tunnelExitIsDirect, .dnsLeak: return .caution
        }
    }
}

public struct WarningContext: Sendable {
    /// ISO country code the exit should be in, or nil when the guard is off.
    public var expectedCountryCode: String?
    /// Whether the default route currently goes through a tunnel interface.
    public var onTunnel: Bool
    /// Fresh direct measurement for the same address family and network as the
    /// snapshot. Nil means unavailable; historical readings must not be used.
    public var directExit: IPInfo?

    public init(expectedCountryCode: String? = nil, onTunnel: Bool = false, directExit: IPInfo? = nil) {
        self.expectedCountryCode = expectedCountryCode
        self.onTunnel = onTunnel
        self.directExit = directExit
    }
}

public func assessWarnings(_ snapshot: ExitSnapshot, context: WarningContext) -> [ExitWarning] {
    var warnings: [ExitWarning] = []
    let primary = snapshot.primary

    // Unknown geo is not a mismatch (the ⚠︎ no-flag state already covers it).
    if let expected = normalizedCountryCode(context.expectedCountryCode),
       let actual = normalizedCountryCode(primary.countryCode),
       expected != actual {
        warnings.append(.unexpectedCountry)
    }

    if let v6 = snapshot.ipv6, ipv6Disagrees(v6, with: primary, onTunnel: context.onTunnel) {
        warnings.append(.ipv6Mismatch)
    }

    if context.onTunnel, let direct = context.directExit, isSameExit(primary, direct) {
        warnings.append(.tunnelExitIsDirect)
    }

    // Unknown country on either side is not a mismatch.
    if let resolver = snapshot.dnsResolver,
       let a = normalizedCountryCode(resolver.countryCode),
       let b = normalizedCountryCode(primary.countryCode),
       a != b {
        warnings.append(.dnsLeak)
    }
    return warnings
}

/// IPv6 disagrees with IPv4 when they exit in different countries, or — on a
/// tunnel, where both should go through the VPN provider — via different ISPs.
/// Missing data on either side is never treated as a disagreement.
private func ipv6Disagrees(_ v6: IPInfo, with v4: IPInfo, onTunnel: Bool) -> Bool {
    if let a = normalizedCountryCode(v6.countryCode), let b = normalizedCountryCode(v4.countryCode), a != b {
        return true
    }
    if onTunnel, let a = normalizedISP(v6.isp), let b = normalizedISP(v4.isp), a != b {
        return true
    }
    return false
}

/// Only an identical address counts. Residential proxies and direct exits
/// can share an ISP without sharing an exit.
public func isSameExit(_ a: IPInfo, _ b: IPInfo) -> Bool {
    if let x = IPv4Address(a.ip), let y = IPv4Address(b.ip) { return x == y }
    if let x = IPv6Address(a.ip), let y = IPv6Address(b.ip) { return x == y }
    return false
}

private func normalizedISP(_ isp: String?) -> String? {
    guard let isp = isp?.trimmingCharacters(in: .whitespaces).lowercased(), !isp.isEmpty else { return nil }
    return isp
}

/// Countries offered for pinning: the current exit, the pinned one, and every
/// country in the history — valid codes only, sorted by display name.
public func expectedCountryChoices(current: String?, pinned: String?, history: [IPChangeEvent]) -> [String] {
    let codes = Set(([current, pinned] + history.map(\.to.countryCode)).compactMap(normalizedCountryCode))
    return codes.map { ($0, countryLabel($0)) }.sorted { $0.1 < $1.1 }.map(\.0)
}

/// Notifications for warnings that newly appeared, plus an all-clear once every
/// warning is gone.
public func warningNotifications(
    previous: [ExitWarning],
    current: [ExitWarning],
    snapshot: ExitSnapshot,
    expectedCountryCode: String?
) -> [AppNotification] {
    let seen = Set(previous)
    var notes = current.filter { !seen.contains($0) }
        .map { notification(for: $0, snapshot: snapshot, expectedCountryCode: expectedCountryCode) }
    if !previous.isEmpty && current.isEmpty {
        notes.append(AppNotification(title: "Exit OK", body: "All exit checks pass again: \(exitSummary(snapshot.primary))"))
    }
    return notes
}

private func notification(for warning: ExitWarning, snapshot: ExitSnapshot, expectedCountryCode: String?) -> AppNotification {
    switch warning {
    case .unexpectedCountry:
        return AppNotification(
            title: "Unexpected exit",
            body: "Exit is \(countryLabel(snapshot.primary.countryCode)) — expected \(countryLabel(expectedCountryCode))."
        )
    case .ipv6Mismatch:
        let via = snapshot.ipv6.map { "via \(exitPlace($0)) (\($0.ip))" } ?? "elsewhere"
        return AppNotification(
            title: "Possible IPv6 leak",
            body: "IPv6 traffic exits \(via), not through your IPv4 exit."
        )
    case .tunnelExitIsDirect:
        return AppNotification(
            title: "Exit matches direct connection",
            body: "A tunnel is active, but the detected exit IP matches the measured direct exit (\(snapshot.primary.ip)). This request may be routed directly by your rules; it does not confirm a VPN-wide leak."
        )
    case .dnsLeak:
        let via = snapshot.dnsResolver.map { "via \(exitPlace($0)) (\($0.ip))" } ?? "elsewhere"
        return AppNotification(
            title: "Possible DNS leak",
            body: "DNS queries are answered \(via), not in your exit's country."
        )
    }
}

/// One-line menu text for a warning, prefixed with its severity glyph.
public func warningLine(_ warning: ExitWarning, snapshot: ExitSnapshot, expectedCountryCode: String?) -> String {
    let text: String
    switch warning {
    case .unexpectedCountry:
        text = "Exit is \(countryLabel(snapshot.primary.countryCode)), expected \(countryLabel(expectedCountryCode))"
    case .ipv6Mismatch:
        let via = snapshot.ipv6.map { "via \(exitPlace($0))" } ?? "elsewhere"
        text = "IPv6 exits \(via) — possible leak"
    case .tunnelExitIsDirect:
        text = "Tunnel active; exit matches measured direct IP (\(snapshot.primary.ip))"
    case .dnsLeak:
        let via = snapshot.dnsResolver.map { "via \(exitPlace($0))" } ?? "elsewhere"
        text = "DNS resolves \(via) — possible leak"
    }
    return "\(warning.severity.glyph) \(text)"
}

/// "🇺🇸 Comcast", "🇺🇸", "Comcast", or the address.
func exitPlace(_ info: IPInfo) -> String {
    let parts = [flag(for: info), info.isp].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? info.ip : parts.joined(separator: " ")
}
