import Foundation
import ExitIPCore

/// Probes a lightweight endpoint (HTTP 204) to confirm real internet reachability
/// and measure round-trip latency. Reuses one URLSession so latency reflects the
/// request RTT rather than a fresh TLS handshake each time.
final class ConnectivityProbe {
    private let url: URL
    private let session: URLSession

    init(url: URL = Config.probeURL, timeout: TimeInterval = Config.probeTimeout) {
        self.url = url
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    /// Returns whether the endpoint is reachable and, if so, the round-trip latency in ms.
    func check() async -> (reachable: Bool, latencyMs: Int?) {
        let start = Date()
        do {
            let (_, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                return (false, nil)
            }
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return (true, ms)
        } catch {
            return (false, nil)
        }
    }
}
