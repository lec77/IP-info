import XCTest
@testable import ExitIPCore

final class IPInfoTests: XCTestCase {
    func testIPOnlyInitDefaultsOptionalsToNil() {
        let info = IPInfo(ip: "203.0.113.42")
        XCTAssertEqual(info.ip, "203.0.113.42")
        XCTAssertNil(info.city)
        XCTAssertNil(info.countryCode)
        XCTAssertNil(info.isp)
    }

    func testEquatable() {
        let a = IPInfo(ip: "1.2.3.4", city: "San Jose", countryCode: "US")
        let b = IPInfo(ip: "1.2.3.4", city: "San Jose", countryCode: "US")
        let c = IPInfo(ip: "5.6.7.8")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
