import Foundation
import Network

private struct IPInfoIOResponse: Decodable {
    let ip: String
    let city: String?
    let region: String?
    let country: String?
    let org: String?
}

private struct IPAPICoResponse: Decodable {
    let ip: String
    let city: String?
    let region: String?
    let country: String?
    let country_name: String?
    let org: String?
}

private struct IPWhoIsResponse: Decodable {
    struct Connection: Decodable {
        let isp: String?
        let org: String?
    }
    let ip: String
    let success: Bool?
    let city: String?
    let region: String?
    let country: String?
    let country_code: String?
    let connection: Connection?
}

private struct IpifyResponse: Decodable {
    let ip: String
}

enum IPParsingError: Error {
    case invalidIPAddress(String)
    case providerError
}

/// True if `string` is a syntactically valid IPv4 or IPv6 address.
func isValidIPAddress(_ string: String) -> Bool {
    IPv4Address(string) != nil || IPv6Address(string) != nil
}

/// Parses an address-only provider's payload. Throws if the result is not a
/// syntactically valid IPv4/IPv6 address — guards against captive portals or
/// provider error pages that return a 200 with a non-IP body, which would
/// otherwise be accepted as a (wrong) IP. A throw drops to the next provider.
func parseAddress(_ data: Data, as format: AddressFormat) throws -> String {
    let ip: String
    switch format {
    case .ipifyJSON:
        ip = try JSONDecoder().decode(IpifyResponse.self, from: data).ip
    case .plainText:
        ip = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard isValidIPAddress(ip) else { throw IPParsingError.invalidIPAddress(ip) }
    return ip
}

/// Parses a geo provider's JSON payload into an `IPInfo`. Throws if `ip` is
/// missing or invalid (see `parseAddress`); a throw drops to the next provider.
func parse(_ data: Data, as format: GeoFormat) throws -> IPInfo {
    let decoder = JSONDecoder()
    let info: IPInfo
    switch format {
    case .ipinfo:
        let r = try decoder.decode(IPInfoIOResponse.self, from: data)
        info = IPInfo(
            ip: r.ip, city: r.city, region: r.region,
            countryCode: r.country,
            countryName: r.country.flatMap(countryName(forCountryCode:)),
            isp: cleanISP(r.org)
        )
    case .ipapi:
        let r = try decoder.decode(IPAPICoResponse.self, from: data)
        info = IPInfo(
            ip: r.ip, city: r.city, region: r.region,
            countryCode: r.country,
            countryName: r.country_name ?? r.country.flatMap(countryName(forCountryCode:)),
            isp: cleanISP(r.org)
        )
    case .ipwhois:
        let r = try decoder.decode(IPWhoIsResponse.self, from: data)
        // ipwho.is answers errors with HTTP 200 + {"success": false}.
        guard r.success ?? true else { throw IPParsingError.providerError }
        info = IPInfo(
            ip: r.ip, city: r.city, region: r.region,
            countryCode: r.country_code,
            countryName: r.country ?? r.country_code.flatMap(countryName(forCountryCode:)),
            isp: cleanISP(r.connection?.isp ?? r.connection?.org)
        )
    }
    guard isValidIPAddress(info.ip) else {
        throw IPParsingError.invalidIPAddress(info.ip)
    }
    return info
}

/// Removes a leading "AS<digits> " token from an org string (e.g. ipinfo.io's `org`).
func cleanISP(_ org: String?) -> String? {
    guard let org, !org.isEmpty else { return nil }
    let parts = org.split(separator: " ", maxSplits: 1)
    if parts.count == 2,
       let first = parts.first,
       first.hasPrefix("AS"),
       first.dropFirst(2).allSatisfy(\.isNumber) {
        return String(parts[1])
    }
    return org
}
