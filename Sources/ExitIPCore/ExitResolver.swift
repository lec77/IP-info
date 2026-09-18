import Foundation

struct ProviderChain<Provider: Sendable>: Sendable {
    let providers: [Provider]

    /// Returns the first provider's successful result, or nil if all fail.
    func resolve<Result>(using fetchOne: (Provider) async -> Result?) async -> Result? {
        for provider in providers {
            if let result = await fetchOne(provider) {
                return result
            }
        }
        return nil
    }
}

/// Geo details per address. An address's location/ISP doesn't change while the
/// app runs, so once looked up it is never fetched again — the periodic poll
/// only ever hits the cheap address endpoints.
public actor GeoCache {
    private var entries: [String: IPInfo] = [:]
    private let limit: Int

    public init(limit: Int = Config.geoCacheLimit) {
        self.limit = limit
    }

    var count: Int { entries.count }

    public func lookup(_ ip: String) -> IPInfo? {
        entries[ip]
    }

    public func store(_ info: IPInfo) {
        if entries.count >= limit { entries.removeAll() }
        entries[info.ip] = info
    }
}

/// Resolves the current exit snapshot: IPv4 and IPv6 addresses concurrently
/// (each through its own fallback chain), then geo for each address — from the
/// cache when the address has been seen before, otherwise through the geo chain.
/// The DNS resolver check runs alongside; its failure never fails the snapshot.
public struct ExitResolver: Sendable {
    public typealias AddressFetch = @Sendable (IPProvider) async -> String?
    public typealias GeoFetch = @Sendable (GeoProvider, String) async -> IPInfo?
    public typealias ResolverFetch = @Sendable () async -> IPInfo?

    private let ipv4: ProviderChain<IPProvider>
    private let ipv6: ProviderChain<IPProvider>
    private let geo: ProviderChain<GeoProvider>
    private let cache: GeoCache
    private let fetchAddress: AddressFetch
    private let fetchGeo: GeoFetch
    private let fetchResolver: ResolverFetch

    public init(
        ipv4Providers: [IPProvider] = Config.ipv4Providers,
        ipv6Providers: [IPProvider] = Config.ipv6Providers,
        geoProviders: [GeoProvider] = Config.geoProviders,
        cache: GeoCache = GeoCache(),
        fetchAddress: @escaping AddressFetch,
        fetchGeo: @escaping GeoFetch,
        fetchResolver: @escaping ResolverFetch = { nil }
    ) {
        self.ipv4 = ProviderChain(providers: ipv4Providers)
        self.ipv6 = ProviderChain(providers: ipv6Providers)
        self.geo = ProviderChain(providers: geoProviders)
        self.cache = cache
        self.fetchAddress = fetchAddress
        self.fetchGeo = fetchGeo
        self.fetchResolver = fetchResolver
    }

    /// Returns nil only when no address at all could be determined.
    /// `includeIPv6: false` skips the IPv6 chain (see `shouldLookupIPv6`);
    /// `includeDNS: false` skips the resolver check (see `carryForwardResolver`).
    public func resolve(includeIPv6: Bool = true, includeDNS: Bool = true) async -> ExitSnapshot? {
        async let v4Task = ipv4.resolve(using: fetchAddress)
        async let v6Task = ipv6Address(enabled: includeIPv6)
        async let resolverTask = resolverInfo(enabled: includeDNS)
        let (v4, v6, resolver) = await (v4Task, v6Task, resolverTask)

        guard let primaryAddress = v4 ?? v6 else { return nil }
        async let primary = geoInfo(for: primaryAddress)
        async let secondary = secondaryGeoInfo(v4: v4, v6: v6)
        return await ExitSnapshot(primary: primary, ipv6: secondary, dnsResolver: resolver)
    }

    private func resolverInfo(enabled: Bool) async -> IPInfo? {
        guard enabled else { return nil }
        return await fetchResolver()
    }

    private func ipv6Address(enabled: Bool) async -> String? {
        guard enabled else { return nil }
        return await ipv6.resolve(using: fetchAddress)
    }

    /// The IPv6 exit is only secondary when there is an IPv4 one.
    private func secondaryGeoInfo(v4: String?, v6: String?) async -> IPInfo? {
        guard v4 != nil, let v6 else { return nil }
        return await geoInfo(for: v6)
    }

    /// Geo for `ip`; degrades to an address-only `IPInfo` if every geo provider
    /// fails. Only complete answers (with a country) are cached, so a degraded
    /// reading is retried on the next poll.
    private func geoInfo(for ip: String) async -> IPInfo {
        if let cached = await cache.lookup(ip) { return cached }
        guard var info = await geo.resolve(using: { await fetchGeo($0, ip) }) else {
            return IPInfo(ip: ip)
        }
        info.ip = ip // the address endpoints are authoritative; geo is decoration
        if info.countryCode != nil { await cache.store(info) }
        return info
    }
}

/// Whether the resolver check is due: never done, or `interval` has elapsed.
public func dnsCheckDue(lastCheck: Date?, now: Date, interval: TimeInterval = Config.dnsCheckInterval) -> Bool {
    guard let lastCheck else { return true }
    return now.timeIntervalSince(lastCheck) >= interval
}

/// A reading without a resolver check keeps the previous reading's resolver,
/// so the DNS-leak warning doesn't clear and re-fire between checks. Whether
/// the carried reading is still current is the caller's problem (it should
/// force a check when the exit changes).
public func carryForwardResolver(_ snapshot: ExitSnapshot, from previous: ExitSnapshot?) -> ExitSnapshot {
    guard snapshot.dnsResolver == nil, let previous else { return snapshot }
    var updated = snapshot
    updated.dnsResolver = previous.dnsResolver
    return updated
}

extension ExitResolver {
    /// The production resolver, backed by URLSession.
    public static func live(timeout: TimeInterval = Config.requestTimeout) -> ExitResolver {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)

        return ExitResolver(
            fetchAddress: { provider in
                var request = URLRequest(url: provider.url)
                request.timeoutInterval = provider.timeout
                guard let data = await get(request, session: session) else { return nil }
                return try? parseAddress(data, as: provider.format)
            },
            fetchGeo: { provider, ip in
                guard let url = provider.url(for: ip),
                      let data = await get(URLRequest(url: url), session: session) else { return nil }
                return try? parse(data, as: provider.format)
            },
            fetchResolver: {
                // A fresh random label each time, so the lookup can't be served from a cache.
                guard let url = Config.dnsProbeURL(token: Config.randomDNSToken()),
                      let data = await get(URLRequest(url: url), session: session) else { return nil }
                return try? parseResolver(data)
            }
        )
    }

    private static func get(_ request: URLRequest, session: URLSession) async -> Data? {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
