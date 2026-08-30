import XCTest
@testable import ExitIPCore

/// Thread-safe call recorder for the resolver's injected fetchers.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var _addresses: [String] = []
    private var _geo: [String] = []
    func address(_ name: String) { lock.lock(); _addresses.append(name); lock.unlock() }
    func geo(_ ip: String) { lock.lock(); _geo.append(ip); lock.unlock() }
    var addresses: [String] { lock.lock(); defer { lock.unlock() }; return _addresses }
    var geo: [String] { lock.lock(); defer { lock.unlock() }; return _geo }
}

final class ExitResolverTests: XCTestCase {
    private static func provider(_ name: String) -> IPProvider {
        IPProvider(name: name, url: URL(string: "https://example.com/\(name)")!, format: .plainText)
    }
    private let v4 = [ExitResolverTests.provider("v4a"), ExitResolverTests.provider("v4b")]
    private let v6 = [ExitResolverTests.provider("v6a")]
    private let geo = [
        GeoProvider(name: "g1", format: .ipinfo, template: "https://g1/{ip}"),
        GeoProvider(name: "g2", format: .ipapi, template: "https://g2/{ip}"),
    ]

    /// A resolver whose address answers are fixed per provider name and whose geo
    /// answers are fixed per address; both record their calls.
    private func makeResolver(
        addresses: [String: String],
        geoAnswers: [String: IPInfo],
        failingGeo: Set<String> = ["g1"],
        cache: GeoCache = GeoCache(),
        calls: Calls
    ) -> ExitResolver {
        ExitResolver(
            ipv4Providers: v4, ipv6Providers: v6, geoProviders: geo, cache: cache,
            fetchAddress: { p in calls.address(p.name); return addresses[p.name] },
            fetchGeo: { g, ip in
                calls.geo("\(g.name):\(ip)")
                if failingGeo.contains(g.name) { return nil }
                return geoAnswers[ip]
            }
        )
    }

    func testDualStackResolvesBothWithGeo() async {
        let calls = Calls()
        let r = makeResolver(
            addresses: ["v4a": "1.1.1.1", "v6a": "2001:db8::1"],
            geoAnswers: ["1.1.1.1": IPInfo(ip: "1.1.1.1", countryCode: "US"),
                         "2001:db8::1": IPInfo(ip: "2001:db8::1", countryCode: "DE")],
            calls: calls)
        let snap = await r.resolve()
        XCTAssertEqual(snap, ExitSnapshot(primary: IPInfo(ip: "1.1.1.1", countryCode: "US"),
                                          ipv6: IPInfo(ip: "2001:db8::1", countryCode: "DE")))
        // Geo chain fell through g1 (failing) to g2 for each address.
        XCTAssertEqual(Set(calls.geo), ["g1:1.1.1.1", "g2:1.1.1.1", "g1:2001:db8::1", "g2:2001:db8::1"])
    }

    func testIPv4OnlyHost() async {
        let calls = Calls()
        let r = makeResolver(addresses: ["v4a": "1.1.1.1"],
                             geoAnswers: ["1.1.1.1": IPInfo(ip: "1.1.1.1", countryCode: "US")], calls: calls)
        let snap = await r.resolve()
        XCTAssertEqual(snap?.primary.countryCode, "US")
        XCTAssertNil(snap?.ipv6)
    }

    func testIPv6OnlyHostPromotesIPv6ToPrimary() async {
        let calls = Calls()
        let r = makeResolver(addresses: ["v6a": "2001:db8::1"],
                             geoAnswers: ["2001:db8::1": IPInfo(ip: "2001:db8::1", countryCode: "DE")], calls: calls)
        let snap = await r.resolve()
        XCTAssertEqual(snap, ExitSnapshot(primary: IPInfo(ip: "2001:db8::1", countryCode: "DE"), ipv6: nil))
    }

    func testIPv6ChainSkippedWhenNotRequested() async {
        let calls = Calls()
        let r = makeResolver(addresses: ["v4a": "1.1.1.1", "v6a": "2001:db8::1"], geoAnswers: [:], calls: calls)
        let snap = await r.resolve(includeIPv6: false)
        XCTAssertEqual(snap?.primary.ip, "1.1.1.1")
        XCTAssertNil(snap?.ipv6)
        XCTAssertFalse(calls.addresses.contains("v6a"))
    }

    func testAddressFallbackWithinFamily() async {
        let calls = Calls()
        let r = makeResolver(addresses: ["v4b": "9.9.9.9"], geoAnswers: [:], calls: calls)
        let snap = await r.resolve()
        XCTAssertEqual(snap?.primary.ip, "9.9.9.9")
        XCTAssertEqual(calls.addresses.filter { $0.hasPrefix("v4") }, ["v4a", "v4b"])
    }

    func testNoAddressAtAllIsNil() async {
        let r = makeResolver(addresses: [:], geoAnswers: [:], calls: Calls())
        let snap = await r.resolve()
        XCTAssertNil(snap)
    }

    func testGeoFailureDegradesToAddressOnly() async {
        let calls = Calls()
        let r = makeResolver(addresses: ["v4a": "1.1.1.1"], geoAnswers: [:], failingGeo: ["g1", "g2"], calls: calls)
        let snap = await r.resolve()
        XCTAssertEqual(snap, ExitSnapshot(primary: IPInfo(ip: "1.1.1.1")))
    }

    func testGeoIsCachedPerAddressAcrossPolls() async {
        let calls = Calls()
        let cache = GeoCache()
        let r = makeResolver(addresses: ["v4a": "1.1.1.1"],
                             geoAnswers: ["1.1.1.1": IPInfo(ip: "1.1.1.1", countryCode: "US")],
                             cache: cache, calls: calls)
        _ = await r.resolve()
        _ = await r.resolve()
        _ = await r.resolve()
        // Address endpoint hit every poll; geo looked up exactly once.
        XCTAssertEqual(calls.addresses.filter { $0 == "v4a" }.count, 3)
        XCTAssertEqual(calls.geo.filter { $0.hasSuffix("1.1.1.1") }, ["g1:1.1.1.1", "g2:1.1.1.1"])
        let count = await cache.count
        XCTAssertEqual(count, 1)
    }

    func testDegradedGeoIsNotCachedSoItRetries() async {
        let calls = Calls()
        let cache = GeoCache()
        let r = makeResolver(addresses: ["v4a": "1.1.1.1"], geoAnswers: [:], failingGeo: ["g1", "g2"],
                             cache: cache, calls: calls)
        _ = await r.resolve()
        _ = await r.resolve()
        XCTAssertEqual(calls.geo.filter { $0 == "g2:1.1.1.1" }.count, 2)
        let count = await cache.count
        XCTAssertEqual(count, 0)
    }

    func testGeoIsRefetchedWhenAddressChanges() async {
        let calls = Calls()
        let cache = GeoCache()
        let answers = ["1.1.1.1": IPInfo(ip: "1.1.1.1", countryCode: "US"),
                       "2.2.2.2": IPInfo(ip: "2.2.2.2", countryCode: "DE")]
        _ = await makeResolver(addresses: ["v4a": "1.1.1.1"], geoAnswers: answers, cache: cache, calls: calls).resolve()
        let snap = await makeResolver(addresses: ["v4a": "2.2.2.2"], geoAnswers: answers, cache: cache, calls: calls).resolve()
        XCTAssertEqual(snap?.primary.countryCode, "DE")
        XCTAssertEqual(calls.geo.filter { $0.hasPrefix("g2:") }, ["g2:1.1.1.1", "g2:2.2.2.2"])
    }

    func testGeoAddressIsOverriddenByAuthoritativeAddress() async {
        // A geo provider echoing a different address must not change the cache key / shown IP.
        let calls = Calls()
        let r = makeResolver(addresses: ["v4a": "1.1.1.1"],
                             geoAnswers: ["1.1.1.1": IPInfo(ip: "7.7.7.7", countryCode: "US")], calls: calls)
        let snap = await r.resolve()
        XCTAssertEqual(snap?.primary.ip, "1.1.1.1")
    }

    func testGeoCacheEvictsWhenFull() async {
        let cache = GeoCache(limit: 2)
        await cache.store(IPInfo(ip: "1"))
        await cache.store(IPInfo(ip: "2"))
        await cache.store(IPInfo(ip: "3"))
        let count = await cache.count
        XCTAssertEqual(count, 1)
        let three = await cache.lookup("3")
        XCTAssertNotNil(three)
    }
}
