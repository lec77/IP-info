import AppKit
import Network
import ExitIPCore

struct SignInCheckResult {
    var status: SignInDetection = .failed
    var url: URL?
    var lines: [String] = []
}

enum SignInDiagnostics {
    static func check(interface: NWInterface?) async -> SignInCheckResult {
        var result = SignInCheckResult()
        guard let interface else {
            result.lines.append("No physical interface available; no default-route fallback attempted.")
            return result
        }
        result.lines.append("Physical interface: \(interface.name)")
        let route = await command("/sbin/route", ["-n", "get", "1.1.1.1"])
        result.lines += route.split(separator: "\n").filter {
            $0.contains("gateway:") || $0.contains("interface:")
        }.map { "Default route: \($0.trimmingCharacters(in: .whitespaces))" }
        let localIP = await command("/usr/sbin/ipconfig", ["getifaddr", interface.name])
        result.lines.append("Local IPv4: \(localIP.isEmpty ? "unavailable" : localIP)")
        let gateway = await command("/usr/sbin/ipconfig", ["getoption", interface.name, "router"])
        result.lines.append("DHCP gateway: \(gateway.isEmpty ? "unavailable" : gateway)")
        let dns = await command("/usr/sbin/ipconfig", ["getoption", interface.name, "domain_name_server"])
        let servers = dns.split(whereSeparator: \.isWhitespace).map(String.init).filter { IPv4Address($0) != nil }
        result.lines.append("DHCP DNS: \(servers.isEmpty ? "unavailable" : servers.joined(separator: ", "))")
        guard !servers.isEmpty else {
            result.lines.append("Cannot resolve the local sign-in trigger without DHCP DNS. No public DNS substituted.")
            return result
        }
        // Both triggers run independently of the normal HTTPS connectivity test.
        for url in [Config.captiveProbeURL, Config.captivePortalSignInURL] {
            guard let host = url.host else { continue }
            var addresses: [String] = []
            for server in servers.prefix(2) {
                addresses = await resolve(host: host, server: server, interface: interface)
                result.lines.append("DNS \(host) via \(server): \(addresses.isEmpty ? "timeout, invalid response, or no usable A record" : addresses.joined(separator: ", "))")
                if !addresses.isEmpty { break }
            }
            for address in addresses.prefix(2) {
                let head = await BoundHTTPProbe.fetchHead(url: url, interface: interface, timeout: 3, connectHost: address)
                result.lines.append("HTTP \(host) via \(interface.name) -> \(address): \(head.map { String($0.statusCode) } ?? "no response")")
                let (status, redirect) = classifySignIn(head: head, requestURL: url, expects204: url == Config.captiveProbeURL)
                if let redirect {
                    result.lines.append("Login origin: \(diagnosticOrigin(redirect)) (path and query omitted)")
                    result.status = .found; result.url = redirect
                    return result
                }
                if status == .notDetected { result.status = .notDetected; return result }
                if status == .suspected { result.status = .suspected }
            }
        }
        return result
    }

    private static func resolve(host: String, server: String, interface: NWInterface) async -> [String] {
        let id = UInt16.random(in: 0...UInt16.max)
        let parameters = NWParameters.udp
        parameters.requiredInterface = interface
        parameters.preferNoProxies = true
        let connection = NWConnection(host: NWEndpoint.Host(server), port: 53, using: parameters)
        let queue = DispatchQueue(label: "com.lec77.ipinfo.local-dns")
        let finish = OnceContinuation<[String]>()
        return await withCheckedContinuation { continuation in
            finish.arm(continuation) { connection.cancel() }
            queue.asyncAfter(deadline: .now() + 2) { finish.resume([]) }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: LocalDNSMessage.query(host: host, id: id), completion: .contentProcessed { error in
                        if error != nil { finish.resume([]) }
                    })
                    connection.receiveMessage { data, _, _, _ in
                        finish.resume(data.map { LocalDNSMessage.addresses($0, id: id) } ?? [])
                    }
                case .failed, .waiting, .cancelled: finish.resume([])
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }

    private static func command(_ executable: String, _ arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process(), pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    // These local configuration commands do not perform network I/O.
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: String(decoding: data.prefix(8192), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
                } catch { continuation.resume(returning: "") }
            }
        }
    }
}

@MainActor
final class DiagnosticJournal {
    private let url: URL
    private var entries: [String]
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IP-info", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("sign-in-diagnostics.json")
        entries = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: url))) ?? []
        entries = Array(entries.suffix(20))
    }
    func append(_ lines: [String]) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        entries.append((["[\(stamp)]"] + lines).joined(separator: "\n"))
        entries = Array(entries.suffix(20))
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
    }
    var text: String {
        "IP-info sign-in diagnostics\nLocal records only. Includes network addresses; excludes credentials, cookies, page contents and URL paths/queries.\n\n" + entries.joined(separator: "\n\n")
    }
}
