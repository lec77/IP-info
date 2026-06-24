public struct IPInfo: Equatable, Sendable {
    public var ip: String
    public var city: String?
    public var region: String?
    public var countryCode: String?
    public var countryName: String?
    public var isp: String?

    public init(
        ip: String,
        city: String? = nil,
        region: String? = nil,
        countryCode: String? = nil,
        countryName: String? = nil,
        isp: String? = nil
    ) {
        self.ip = ip
        self.city = city
        self.region = region
        self.countryCode = countryCode
        self.countryName = countryName
        self.isp = isp
    }
}
