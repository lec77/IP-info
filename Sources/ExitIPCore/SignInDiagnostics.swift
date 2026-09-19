import Foundation
import Network

public enum SignInDetection: String, Sendable, Codable {
    case notChecked, checking, notDetected, found, suspected, failed
    public var title: String {
        switch self {
        case .notChecked: return "Sign-in: Not checked"
        case .checking: return "Sign-in: Checking physical network…"
        case .notDetected: return "Sign-in: No portal detected"
        case .found: return "Sign-in: Login page found"
        case .suspected: return "Sign-in: Possible portal; no login URL"
        case .failed: return "Sign-in detection failed"
        }
    }
}

/// Logs keep only the destination origin, never paths, tokens, cookies or forms.
public func diagnosticOrigin(_ url: URL) -> String {
    guard let host = url.host, let scheme = url.scheme else { return "unknown" }
    return "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
}

public func classifySignIn(head: HTTPResponseHead?, requestURL: URL, expects204: Bool) -> (SignInDetection, URL?) {
    guard let head else { return (.failed, nil) }
    if let redirect = portalRedirectURL(from: head, requestURL: requestURL),
       redirect.user == nil, redirect.password == nil {
        // A normal HTTP→HTTPS upgrade is not a login page.
        if redirect.scheme == "https", redirect.host == requestURL.host,
           redirect.path == requestURL.path { return (.failed, nil) }
        return (.found, redirect)
    }
    if expects204 && head.statusCode == 204 { return (.notDetected, nil) }
    if head.statusCode == 511 || (expects204 && head.statusCode == 200) { return (.suspected, nil) }
    // An arbitrary 200, 403 or 500 does not establish either connectivity or a portal.
    return (.failed, nil)
}

/// Minimal A query/response codec for the DHCP-provided resolver. No global DNS.
public enum LocalDNSMessage {
    public static func query(host: String, id: UInt16) -> Data {
        var bytes: [UInt8] = [UInt8(id >> 8), UInt8(id & 255), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0]
        for label in host.split(separator: ".") {
            guard label.utf8.count <= 63 else { return Data() }
            bytes.append(UInt8(label.utf8.count)); bytes += label.utf8
        }
        bytes += [0, 0, 1, 0, 1]
        return Data(bytes)
    }

    public static func addresses(_ data: Data, id: UInt16) -> [String] {
        let b = [UInt8](data)
        func word(_ i: Int) -> Int { Int(b[i]) << 8 | Int(b[i + 1]) }
        guard b.count >= 12, word(0) == Int(id), b[2] & 0x80 != 0,
              b[2] & 0x02 == 0, b[3] & 0x0f == 0 else { return [] }
        var i = 12
        func skipName() -> Bool {
            while i < b.count {
                let n = Int(b[i]); i += 1
                if n == 0 { return true }
                if n & 0xc0 == 0xc0 {
                    guard i < b.count else { return false }
                    i += 1; return true
                }
                guard n <= 63, i + n <= b.count else { return false }
                i += n
            }
            return false
        }
        for _ in 0..<word(4) {
            guard skipName(), i + 4 <= b.count else { return [] }; i += 4
        }
        var result: [String] = []
        for _ in 0..<word(6) {
            guard skipName(), i + 10 <= b.count else { return [] }
            let type = word(i), klass = word(i + 2), length = word(i + 8)
            i += 10
            guard i + length <= b.count else { return [] }
            if type == 1 && klass == 1 && length == 4 {
                // Never attempt to reach a Fake-IP on the physical interface.
                if !(b[i] == 198 && (b[i + 1] == 18 || b[i + 1] == 19)) {
                    result.append(b[i..<i+4].map(String.init).joined(separator: "."))
                }
            }
            i += length
        }
        return Array(result.prefix(3))
    }
}
