import XCTest
@testable import ExitIPCore

final class ProviderFallbackTests: XCTestCase {
    private func provider(_ name: String) -> IPProvider {
        IPProvider(name: name, url: URL(string: "https://example.com/\(name)")!, kind: .ipify)
    }
    private lazy var chain = ProviderChain(providers: [provider("a"), provider("b"), provider("c")])

    func testFirstSuccessWins() async {
        let result = await chain.resolve { p in
            p.name == "a" ? IPInfo(ip: "10.0.0.1") : IPInfo(ip: "10.0.0.99")
        }
        XCTAssertEqual(result, IPInfo(ip: "10.0.0.1"))
    }

    func testFallsThroughToLast() async {
        let result = await chain.resolve { p in
            p.name == "c" ? IPInfo(ip: "10.0.0.3") : nil
        }
        XCTAssertEqual(result, IPInfo(ip: "10.0.0.3"))
    }

    func testAllFailReturnsNil() async {
        let result = await chain.resolve { _ in nil }
        XCTAssertNil(result)
    }

    func testDefaultProviderOrder() {
        XCTAssertEqual(Config.providers.map(\.name), ["ipinfo.io", "ipapi.co", "ipify"])
    }
}
