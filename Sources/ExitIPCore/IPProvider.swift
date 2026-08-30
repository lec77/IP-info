import Foundation

/// Payload shape of an address-only endpoint.
public enum AddressFormat: Sendable {
    /// `{"ip": "…"}`
    case ipifyJSON
    /// The bare address, possibly with trailing whitespace.
    case plainText
}

/// Payload shape of a geo/ISP lookup endpoint.
public enum GeoFormat: Sendable {
    case ipinfo, ipapi, ipwhois
}

/// A cheap "what is my address" endpoint. One list per address family; the
/// endpoint's host must be reachable only over that family so the answer is
/// unambiguous (e.g. `api.ipify.org` is IPv4-only, `api6.ipify.org` IPv6-only).
public struct IPProvider: Sendable {
    public let name: String
    public let url: URL
    public let format: AddressFormat
    public let timeout: TimeInterval

    public init(name: String, url: URL, format: AddressFormat, timeout: TimeInterval = Config.requestTimeout) {
        self.name = name
        self.url = url
        self.format = format
        self.timeout = timeout
    }
}

/// A geo/ISP lookup for a specific address. `{ip}` in the template is replaced
/// with the address being looked up.
public struct GeoProvider: Sendable {
    public let name: String
    public let format: GeoFormat
    public let template: String

    public init(name: String, format: GeoFormat, template: String) {
        self.name = name
        self.format = format
        self.template = template
    }

    public func url(for ip: String) -> URL? {
        URL(string: template.replacingOccurrences(of: "{ip}", with: ip))
    }
}
