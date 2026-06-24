import XCTest
@testable import ExitIPCore

final class IPInfoParsingTests: XCTestCase {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testParseIPInfoIO() throws {
        let json = """
        {"ip":"203.0.113.42","city":"San Jose","region":"California","country":"US","org":"AS13335 Cloudflare, Inc."}
        """
        let info = try parse(data(json), as: .ipinfo)
        XCTAssertEqual(info, IPInfo(
            ip: "203.0.113.42", city: "San Jose", region: "California",
            countryCode: "US", countryName: "United States", isp: "Cloudflare, Inc."
        ))
    }

    func testParseIPAPICo() throws {
        let json = """
        {"ip":"203.0.113.42","city":"San Jose","region":"California","country":"US","country_name":"United States","org":"Cloudflare, Inc."}
        """
        let info = try parse(data(json), as: .ipapi)
        XCTAssertEqual(info, IPInfo(
            ip: "203.0.113.42", city: "San Jose", region: "California",
            countryCode: "US", countryName: "United States", isp: "Cloudflare, Inc."
        ))
    }

    func testParseIpify() throws {
        let info = try parse(data(#"{"ip":"203.0.113.42"}"#), as: .ipify)
        XCTAssertEqual(info, IPInfo(ip: "203.0.113.42"))
    }

    func testParseMalformedThrows() {
        XCTAssertThrowsError(try parse(data(#"{"foo":"bar"}"#), as: .ipinfo))
    }

    func testParseRejectsInvalidIPValue() {
        // 200-OK body that decodes but whose IP is garbage (captive portal / error page).
        XCTAssertThrowsError(try parse(data(#"{"ip":"not-an-ip"}"#), as: .ipify))
        XCTAssertThrowsError(try parse(data(#"{"ip":"login.example.com","city":"X","country":"US"}"#), as: .ipinfo))
        XCTAssertThrowsError(try parse(data(#"{"ip":""}"#), as: .ipify))
    }

    func testParseAcceptsIPv6() throws {
        let info = try parse(data(#"{"ip":"2001:db8::1"}"#), as: .ipify)
        XCTAssertEqual(info.ip, "2001:db8::1")
    }

    func testCleanISP() {
        XCTAssertEqual(cleanISP("AS13335 Cloudflare, Inc."), "Cloudflare, Inc.")
        XCTAssertEqual(cleanISP("Cloudflare, Inc."), "Cloudflare, Inc.")
        XCTAssertNil(cleanISP(nil))
        XCTAssertNil(cleanISP(""))
    }
}
