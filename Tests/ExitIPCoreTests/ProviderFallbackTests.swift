import XCTest
@testable import ExitIPCore

final class ProviderFallbackTests: XCTestCase {
    private func provider(_ name: String) -> IPProvider {
        IPProvider(name: name, url: URL(string: "https://example.com/\(name)")!, format: .ipifyJSON)
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
        let result = await chain.resolve { _ in nil as IPInfo? }
        XCTAssertNil(result)
    }

    func testDefaultProviderOrder() {
        XCTAssertEqual(Config.ipv4Providers.map(\.name), ["ipify", "icanhazip"])
        XCTAssertEqual(Config.ipv6Providers.map(\.name), ["ipify6", "icanhazip6"])
        XCTAssertEqual(Config.geoProviders.map(\.name), ["ipinfo.io", "ipwho.is", "ipapi.co"])
    }

    func testIPv6ProvidersUseShortTimeout() {
        for p in Config.ipv6Providers { XCTAssertEqual(p.timeout, Config.ipv6Timeout) }
        for p in Config.ipv4Providers { XCTAssertEqual(p.timeout, Config.requestTimeout) }
        XCTAssertLessThan(Config.ipv6Timeout, Config.requestTimeout)
    }

    func testGeoProviderURLSubstitutesAddress() {
        let p = GeoProvider(name: "x", format: .ipinfo, template: "https://ipinfo.io/{ip}/json")
        XCTAssertEqual(p.url(for: "8.8.8.8")?.absoluteString, "https://ipinfo.io/8.8.8.8/json")
        XCTAssertEqual(p.url(for: "2001:db8::1")?.absoluteString, "https://ipinfo.io/2001:db8::1/json")
        for g in Config.geoProviders { XCTAssertNotNil(g.url(for: "2001:db8::1"), g.name) }
    }

    func testGenericChainWorksForGeoProviders() async {
        let chain = ProviderChain(providers: Config.geoProviders)
        let result = await chain.resolve { $0.format == .ipwhois ? "hit" : nil }
        XCTAssertEqual(result, "hit")
    }
}
