import Foundation
import ExitIPCore

/// Probes a lightweight endpoint (expected HTTP 204) to confirm real internet
/// reachability, detect captive portals, and measure round-trip latency. Reuses
/// one URLSession so latency reflects the request RTT rather than a fresh
/// connection each time. Redirects are refused so a portal's bounce to its login
/// page shows up as the 3xx it is. When the HTTPS probe gets no response at all,
/// a plain-HTTP probe is tried, since that is what portals can actually intercept.
final class ConnectivityProbe: NSObject, URLSessionTaskDelegate {
    private let url: URL
    private let captiveURL: URL
    private let session: URLSession

    init(url: URL = Config.probeURL, captiveURL: URL = Config.captiveProbeURL, timeout: TimeInterval = Config.probeTimeout) {
        self.url = url
        self.captiveURL = captiveURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    /// Returns the verdict and, when reachable, the round-trip latency in ms.
    func check() async -> (verdict: ProbeVerdict, latencyMs: Int?) {
        let start = Date()
        let status = await statusCode(of: url)
        let latency = Int(Date().timeIntervalSince(start) * 1000)
        let fallback = status == nil ? await statusCode(of: captiveURL) : nil
        let verdict = probeVerdict(statusCode: status ?? fallback)
        return (verdict, verdict == .reachable ? latency : nil)
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
