import Foundation
import Network

/// A fresh measurement, never a persisted or inferred baseline. Numeric HTTPS
/// endpoints avoid system DNS/Fake-IP; TLS certificate validation stays enabled.
public struct DirectExitProbe: Sendable {
    public typealias Fetch = @Sendable ([String]) async -> Data?
    private let fetch: Fetch

    public init(fetch: @escaping Fetch = DirectExitProbe.runCurl) {
        self.fetch = fetch
    }

    public func measure(interface: ActiveInterface?, matching address: String) async -> IPInfo? {
        guard let interface, interface.kind.isPhysical,
              IPv4Address(address) != nil || IPv6Address(address) != nil else { return nil }
        let ipv6 = IPv6Address(address) != nil
        let endpoints = ipv6 ? ["[2606:4700:4700::1111]", "[2606:4700:4700::1001]"] : ["1.1.1.1", "1.0.0.1"]
        for endpoint in endpoints {
            // if! forces an interface name: curl must fail if it cannot bind it.
            // -q must be first to ignore ~/.curlrc. No proxy, redirects or DNS.
            let arguments = ["-q", "--proxy", "", "--noproxy", "*",
                             "--interface", "if!\(interface.name)",
                             "--connect-timeout", "3", "--max-time", "5",
                             "--max-filesize", "4096", "--proto", "=https",
                             "--fail", "--silent", ipv6 ? "--ipv6" : "--ipv4",
                             "https://\(endpoint)/cdn-cgi/trace"]
            if let data = await fetch(arguments), let ip = Self.parse(data, ipv6: ipv6) {
                return IPInfo(ip: ip)
            }
        }
        // Numeric trace addresses are unreachable on some networks. Resolve a
        // regular address provider over interface-bound HTTPS DNS, then pin its
        // address so system DNS/Fake-IP cannot re-enter the request path.
        let host = ipv6 ? "ipv6.icanhazip.com" : "ipv4.icanhazip.com"
        let common = ["-q", "--proxy", "", "--noproxy", "*",
                      "--interface", "if!\(interface.name)",
                      "--connect-timeout", "3", "--max-time", "5",
                      "--max-filesize", "4096", "--proto", "=https", "--fail", "--silent"]
        let dnsArguments = common + ["--resolve", "dns.alidns.com:443:223.5.5.5",
                                     "https://dns.alidns.com/resolve?name=\(host)&type=\(ipv6 ? "AAAA" : "A")"]
        guard let dnsData = await fetch(dnsArguments) else { return nil }
        let addresses = Self.parseDNS(dnsData, ipv6: ipv6)
        guard !addresses.isEmpty else { return nil }
        let pinned = addresses.map { ipv6 ? "[\($0)]" : $0 }.joined(separator: ",")
        let arguments = common + [ipv6 ? "--ipv6" : "--ipv4", "--resolve",
                                  "\(host):443:\(pinned)", "https://\(host)/"]
        guard let data = await fetch(arguments), data.count <= 4096,
              let ip = try? parseAddress(data, as: .plainText),
              ipv6 ? IPv6Address(ip) != nil : IPv4Address(ip) != nil else { return nil }
        return IPInfo(ip: ip)
    }

    static func parseDNS(_ data: Data, ipv6: Bool) -> [String] {
        struct Response: Decodable {
            struct Record: Decodable { let type: Int; let data: String }
            let Status: Int
            let Answer: [Record]?
        }
        guard data.count <= 4096, let response = try? JSONDecoder().decode(Response.self, from: data),
              response.Status == 0 else { return [] }
        return (response.Answer ?? []).filter {
            $0.type == (ipv6 ? 28 : 1) && (ipv6 ? IPv6Address($0.data) != nil : IPv4Address($0.data) != nil)
        }.prefix(4).map(\.data)
    }

    static func parse(_ data: Data, ipv6: Bool) -> String? {
        guard data.count <= 4096, let text = String(data: data, encoding: .utf8) else { return nil }
        let values = text.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("ip=") }
        guard values.count == 1 else { return nil }
        let ip = String(values[0].dropFirst(3))
        if ipv6 { return IPv6Address(ip).map { _ in ip } }
        return IPv4Address(ip).map { _ in ip }
    }

    /// Use the system HTTPS client for bounded HTTP parsing and certificate
    /// validation. Process arguments are passed directly, never through a shell.
    public static func runCurl(_ arguments: [String]) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                process.arguments = arguments
                // Avoid environment overrides for TLS trust, proxies and config.
                process.environment = [:]
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0 ? data : nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
