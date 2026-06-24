import Foundation

public enum ProviderKind: Sendable {
    case ipinfo, ipapi, ipify
}

public struct IPProvider: Sendable {
    public let name: String
    public let url: URL
    public let kind: ProviderKind

    public init(name: String, url: URL, kind: ProviderKind) {
        self.name = name
        self.url = url
        self.kind = kind
    }
}
