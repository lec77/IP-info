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
    /// A tunnel interface carries the default route, yet the exit is the ISP
    /// seen when no tunnel was up — traffic is not actually going through it.
    case tunnelExitIsHome

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
        case .ipv6Mismatch, .tunnelExitIsHome: return .caution
        }
    }
}

public struct WarningContext: Sendable {
    /// ISO country code the exit should be in, or nil when the guard is off.
    public var expectedCountryCode: String?
    /// Whether the default route currently goes through a tunnel interface.
    public var onTunnel: Bool
    /// The exit last seen while *not* on a tunnel — i.e. the plain ISP connection.
    public var homeExit: IPInfo?

    public init(expectedCountryCode: String? = nil, onTunnel: Bool = false, homeExit: IPInfo? = nil) {
        self.expectedCountryCode = expectedCountryCode
        self.onTunnel = onTunnel
        self.homeExit = homeExit
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

    if context.onTunnel, let home = context.homeExit, isSameExit(primary, home) {
        warnings.append(.tunnelExitIsHome)
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

/// Same address, or (both known) the same ISP.
public func isSameExit(_ a: IPInfo, _ b: IPInfo) -> Bool {
    if a.ip == b.ip { return true }
    if let x = normalizedISP(a.isp), let y = normalizedISP(b.isp) { return x == y }
    return false
}

private func normalizedISP(_ isp: String?) -> String? {
    guard let isp = isp?.trimmingCharacters(in: .whitespaces).lowercased(), !isp.isEmpty else { return nil }
    return isp
}

/// The exit to remember as "home" (the plain ISP connection) after a good
/// reading: the current exit when the default route is a known non-tunnel
/// interface, otherwise whatever was remembered before — an unknown interface
/// might be a tunnel.
public func homeExit(after snapshot: ExitSnapshot, via interface: ActiveInterface?, previous: IPInfo?) -> IPInfo? {
    guard let interface, interface.kind != .tunnel else { return previous }
    return snapshot.primary
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
    case .tunnelExitIsHome:
        return AppNotification(
            title: "Possible VPN leak",
            body: "A tunnel is up, but the exit is your usual ISP\(ispSuffix(snapshot.primary.isp))."
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
    case .tunnelExitIsHome:
        text = "Tunnel up, but exit is your usual ISP\(ispSuffix(snapshot.primary.isp))"
    }
    return "\(warning.severity.glyph) \(text)"
}

private func ispSuffix(_ isp: String?) -> String {
    isp.map { " (\($0))" } ?? ""
}

/// "🇺🇸 Comcast", "🇺🇸", "Comcast", or the address.
private func exitPlace(_ info: IPInfo) -> String {
    let parts = [flag(for: info), info.isp].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? info.ip : parts.joined(separator: " ")
}
