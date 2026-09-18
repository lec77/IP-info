/// Geo/ISP details for one address (IPv4 or IPv6).
public struct IPInfo: Equatable, Sendable, Codable {
    public var ip: String
    public var city: String?
    public var region: String?
    public var countryCode: String?
    public var countryName: String?
    public var isp: String?

    public init(
        ip: String,
        city: String? = nil,
        region: String? = nil,
        countryCode: String? = nil,
        countryName: String? = nil,
        isp: String? = nil
    ) {
        self.ip = ip
        self.city = city
        self.region = region
        self.countryCode = countryCode
        self.countryName = countryName
        self.isp = isp
    }
}

/// One observation of the machine's exit addresses.
public struct ExitSnapshot: Equatable, Sendable {
    /// The IPv4 exit when the host has one, otherwise the IPv6 exit.
    public var primary: IPInfo
    /// The IPv6 exit, when the host has IPv6 connectivity *in addition* to IPv4.
    /// `nil` when there is no IPv6 path, or when IPv6 is already the primary.
    public var ipv6: IPInfo?
    /// The resolver that answers this machine's DNS queries, as seen by an
    /// authoritative server, when that lookup succeeded.
    public var dnsResolver: IPInfo?

    public init(primary: IPInfo, ipv6: IPInfo? = nil, dnsResolver: IPInfo? = nil) {
        self.primary = primary
        self.ipv6 = ipv6
        self.dnsResolver = dnsResolver
    }
}
