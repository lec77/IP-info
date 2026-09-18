import Foundation
import Network
import ExitIPCore

struct ProbeResult {
    var verdict: ProbeVerdict
    /// Round-trip latency of the HTTPS probe, when it succeeded.
    var latencyMs: Int?
    /// Where a captive portal redirected the plain-HTTP probe, if it did.
    var portalRedirect: URL?
}

/// Probes a lightweight endpoint (expected HTTP 204) to confirm real internet
/// reachability, detect captive portals, and measure round-trip latency. Reuses
/// one URLSession so latency reflects the request RTT rather than a fresh
/// connection each time. Redirects are refused so a portal's bounce to its login
/// page shows up as the 3xx it is.
///
/// When the HTTPS probe gets no response at all, a plain-HTTP probe is sent
/// *bound to the physical interface*: plain HTTP is what portals can actually
/// intercept, and binding sidesteps any VPN/proxy tunnel (including its DNS
/// hijack) that would otherwise swallow the request and hide the portal — or
/// turn its own outage into a false "captive portal".
final class ConnectivityProbe: NSObject, URLSessionTaskDelegate {
    private let url: URL
    private let captiveURL: URL
    private let timeout: TimeInterval
    private let session: URLSession

    init(url: URL = Config.probeURL, captiveURL: URL = Config.captiveProbeURL, timeout: TimeInterval = Config.probeTimeout) {
        self.url = url
        self.captiveURL = captiveURL
        self.timeout = timeout
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    /// `physicalInterface` is what the fallback probe binds to; nil probes over
    /// the default route like the HTTPS one.
    func check(physicalInterface: NWInterface?) async -> ProbeResult {
        let start = Date()
        if let status = await statusCode(of: url) {
            let verdict = probeVerdict(statusCode: status)
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            return ProbeResult(verdict: verdict, latencyMs: verdict == .reachable ? latency : nil)
        }
        let head = await BoundHTTPProbe.fetchHead(url: captiveURL, interface: physicalInterface, timeout: timeout)
        return ProbeResult(
            verdict: probeVerdict(statusCode: head?.statusCode),
            portalRedirect: head.flatMap { portalRedirectURL(from: $0, requestURL: captiveURL) }
        )
    }

    /// The response status, or nil if there was no HTTP response at all.
    private func statusCode(of url: URL) async -> Int? {
        do {
            let (_, response) = try await session.data(from: url, delegate: self)
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil) // don't follow; the 3xx becomes the final response
    }
}

/// A minimal HTTP/1.1 GET over a raw TCP connection that can be pinned to one
/// interface — something URLSession can't do. Only the response head is read;
/// a portal's redirect Location is all that's wanted from it.
enum BoundHTTPProbe {
    private static let maxHeadBytes = 64 * 1024

    static func fetchHead(url: URL, interface: NWInterface?, timeout: TimeInterval) async -> HTTPResponseHead? {
        guard let host = url.host, !host.isEmpty else { return nil }
        let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 80)) ?? 80
        let parameters = NWParameters.tcp
        parameters.requiredInterface = interface
        parameters.preferNoProxies = true
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        let queue = DispatchQueue(label: "com.lec77.ipinfo.bound-probe")
        let finish = OnceContinuation<HTTPResponseHead?>()

        return await withCheckedContinuation { continuation in
            finish.arm(continuation) { connection.cancel() }
            queue.asyncAfter(deadline: .now() + timeout) { finish.resume(nil) }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data(request(for: url, host: host).utf8), completion: .contentProcessed { error in
                        if error != nil { finish.resume(nil) }
                    })
                    receiveHead(on: connection, buffer: Data(), finish: finish)
                case .waiting, .failed, .cancelled:
                    // .waiting is "refused / no route, will retry on a path change";
                    // for a one-shot probe that's a failure, not something to sit out.
                    finish.resume(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private static func request(for url: URL, host: String) -> String {
        var target = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty { target += "?\(query)" }
        return "GET \(target) HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: IP-info connectivity probe\r\n"
            + "Accept: */*\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
    }

    private static func receiveHead(on connection: NWConnection, buffer: Data, finish: OnceContinuation<HTTPResponseHead?>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { chunk, _, isComplete, error in
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            if httpHeadIsComplete(buffer) || isComplete || error != nil || buffer.count > maxHeadBytes {
                finish.resume(parseHTTPResponseHead(buffer))
            } else {
                receiveHead(on: connection, buffer: buffer, finish: finish)
            }
        }
    }
}

/// Resumes a continuation at most once, whichever of several callbacks
/// (response, failure, timeout) gets there first, then runs the cleanup.
private final class OnceContinuation<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    private var cleanup: (() -> Void)?

    func arm(_ continuation: CheckedContinuation<T, Never>, cleanup: @escaping () -> Void) {
        lock.lock(); defer { lock.unlock() }
        self.continuation = continuation
        self.cleanup = cleanup
    }

    func resume(_ value: T) {
        lock.lock()
        let continuation = self.continuation
        let cleanup = self.cleanup
        self.continuation = nil
        self.cleanup = nil
        lock.unlock()
        continuation?.resume(returning: value)
        cleanup?()
    }
}

/// Which interface the default route actually uses. `NWPathMonitor` doesn't
/// list a proxy's TUN device that hijacks the route (Clash, Surge, …), but a
/// connection's own path does — so this "connects" a UDP socket (which sends
/// nothing) to a public address and reads the interface off it.
enum RouteProbe {
    static func defaultRouteInterface(timeout: TimeInterval = 1) async -> ActiveInterface? {
        let connection = NWConnection(host: "1.1.1.1", port: 53, using: .udp)
        let queue = DispatchQueue(label: "com.lec77.ipinfo.route-probe")
        let finish = OnceContinuation<ActiveInterface?>()
        return await withCheckedContinuation { continuation in
            finish.arm(continuation) { connection.cancel() }
            queue.asyncAfter(deadline: .now() + timeout) { finish.resume(nil) }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let interface = connection.currentPath?.availableInterfaces.first.map {
                        ActiveInterface(name: $0.name, kind: interfaceKind(name: $0.name, type: $0.type))
                    }
                    finish.resume(interface)
                case .waiting, .failed, .cancelled:
                    finish.resume(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }
}
