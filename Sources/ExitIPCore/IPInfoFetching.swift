import Foundation

struct ProviderChain: Sendable {
    let providers: [IPProvider]

    /// Returns the first provider's successful result, or nil if all fail.
    func resolve(using fetchOne: (IPProvider) async -> IPInfo?) async -> IPInfo? {
        for provider in providers {
            if let info = await fetchOne(provider) {
                return info
            }
        }
        return nil
    }
}

public protocol IPInfoFetching: Sendable {
    /// Returns the current exit IP info, or nil if every provider failed.
    func fetch() async -> IPInfo?
}

public final class URLSessionIPInfoFetcher: IPInfoFetching, Sendable {
    private let chain: ProviderChain
    private let session: URLSession

    public init(providers: [IPProvider] = Config.providers, timeout: TimeInterval = Config.requestTimeout) {
        self.chain = ProviderChain(providers: providers)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    public func fetch() async -> IPInfo? {
        await chain.resolve { [session] provider in
            do {
                let (data, response) = try await session.data(from: provider.url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    return nil
                }
                return try parse(data, as: provider.kind)
            } catch {
                return nil
            }
        }
    }
}
