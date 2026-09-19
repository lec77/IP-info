import XCTest
@testable import ExitIPCore

final class SignInDiagnosticsTests: XCTestCase {
    private let trigger = URL(string: "http://www.gstatic.com/generate_204")!

    func testRealRedirectIsKeptInMemoryButTokensAreExcludedFromDiagnostics() {
        let head = HTTPResponseHead(statusCode: 302, headers: ["location": "http://10.0.0.1/login/session-secret?token=secret#password"])
        let (status, url) = classifySignIn(head: head, requestURL: trigger, expects204: true)
        XCTAssertEqual(status, .found)
        XCTAssertEqual(url?.query, "token=secret")
        XCTAssertEqual(diagnosticOrigin(url!), "http://10.0.0.1")
    }

    func testCredentialsAndNonHTTPRedirectsAreNotOfferedAsLoginPages() {
        for target in ["file:///etc/passwd", "javascript:alert(1)", "http://user:password@10.0.0.1/login"] {
            let (status, url) = classifySignIn(head: HTTPResponseHead(statusCode: 302, headers: ["location": target]), requestURL: trigger, expects204: true)
            XCTAssertEqual(status, .failed)
            XCTAssertNil(url)
        }
    }

    func testUpgradeAndHTTPFailuresDoNotClaimPortalDetected() {
        let upgrade = HTTPResponseHead(statusCode: 301, headers: ["location": "https://www.gstatic.com/generate_204"])
        XCTAssertEqual(classifySignIn(head: upgrade, requestURL: trigger, expects204: true).0, .failed)
        for code in [403, 404, 500, 503] {
            XCTAssertEqual(classifySignIn(head: HTTPResponseHead(statusCode: code), requestURL: trigger, expects204: true).0, .failed)
        }
        XCTAssertEqual(classifySignIn(head: nil, requestURL: trigger, expects204: true).0, .failed)
    }

    func testKnownSuccessAndUnlocatedPortalRemainDistinct() {
        XCTAssertEqual(classifySignIn(head: HTTPResponseHead(statusCode: 204), requestURL: trigger, expects204: true).0, .notDetected)
        XCTAssertEqual(classifySignIn(head: HTTPResponseHead(statusCode: 200), requestURL: trigger, expects204: true).0, .suspected)
        XCTAssertEqual(classifySignIn(head: HTTPResponseHead(statusCode: 511), requestURL: trigger, expects204: true).0, .suspected)
        XCTAssertEqual(classifySignIn(head: HTTPResponseHead(statusCode: 200), requestURL: Config.captivePortalSignInURL, expects204: false).0, .failed)
    }

    private func response(ip: [UInt8] = [10, 0, 0, 1]) -> Data {
        var bytes = [UInt8](LocalDNSMessage.query(host: "example.com", id: 0x1234))
        bytes[2] = 0x81; bytes[3] = 0x80; bytes[7] = 1
        bytes += [0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4] + ip
        return Data(bytes)
    }

    func testLocalDNSParsesCompressedIPv4Answer() {
        XCTAssertEqual(LocalDNSMessage.addresses(response(), id: 0x1234), ["10.0.0.1"])
    }

    func testLocalDNSRejectsWrongTransactionTruncationAndFakeIP() {
        XCTAssertEqual(LocalDNSMessage.addresses(response(), id: 0x5678), [])
        let data = response()
        for length in 0..<data.count {
            XCTAssertEqual(LocalDNSMessage.addresses(data.prefix(length), id: 0x1234), [])
        }
        XCTAssertEqual(LocalDNSMessage.addresses(response(ip: [198, 18, 0, 1]), id: 0x1234), [])
        XCTAssertEqual(LocalDNSMessage.addresses(response(ip: [198, 19, 255, 1]), id: 0x1234), [])
    }

    func testDNSErrorAndTruncatedFlagNeverProduceAnAddress() {
        var bytes = [UInt8](response())
        bytes[3] = 0x83
        XCTAssertEqual(LocalDNSMessage.addresses(Data(bytes), id: 0x1234), [])
        bytes[3] = 0x80; bytes[2] = 0x83
        XCTAssertEqual(LocalDNSMessage.addresses(Data(bytes), id: 0x1234), [])
    }
}
