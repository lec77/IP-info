import Network

public enum InterfaceKind: Sendable, Equatable {
    case wifi, wired, cellular, tunnel, loopback, other

    /// Traffic on this interface leaves the machine directly — the interface to
    /// bind to when a request must not go through a tunnel.
    public var isPhysical: Bool {
        switch self {
        case .wifi, .wired, .cellular: return true
        case .tunnel, .loopback, .other: return false
        }
    }
}

/// The interface carrying the default route.
public struct ActiveInterface: Sendable, Equatable {
    public var name: String
    public var kind: InterfaceKind

    public init(name: String, kind: InterfaceKind) {
        self.name = name
        self.kind = kind
    }
}

/// Interface names macOS gives to VPN/tunnel devices: `utun` (most VPN apps,
/// WireGuard, Tailscale), `ipsec` (built-in IKEv2), `ppp` (L2TP/PPTP), plus the
/// generic tun/tap/wg names.
private let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap", "wg"]

public func interfaceKind(name: String, type: NWInterface.InterfaceType) -> InterfaceKind {
    switch type {
    case .wifi: return .wifi
    case .wiredEthernet: return .wired
    case .cellular: return .cellular
    case .loopback: return .loopback
    case .other:
        return tunnelPrefixes.contains(where: { name.hasPrefix($0) }) ? .tunnel : .other
    @unknown default:
        return .other
    }
}

public func interfaceLine(_ interface: ActiveInterface?) -> String {
    guard let interface else { return "Via: —" }
    let label: String
    switch interface.kind {
    case .wifi: label = "Wi-Fi"
    case .wired: label = "Ethernet"
    case .cellular: label = "Cellular"
    case .tunnel: label = "VPN tunnel"
    case .loopback: label = "Loopback"
    case .other: label = "Other"
    }
    return "Via: \(label) (\(interface.name))"
}

/// Whether to look up the IPv6 exit. Skipped when the system reports no IPv6
/// route — unless the default route is a tunnel: a tunnel that doesn't carry
/// IPv6 is exactly the setup that leaks it over the underlying interface, so on
/// a tunnel the lookup runs regardless of what the path claims.
public func shouldLookupIPv6(pathSupportsIPv6: Bool, interface: ActiveInterface?) -> Bool {
    pathSupportsIPv6 || interface?.kind == .tunnel
}
