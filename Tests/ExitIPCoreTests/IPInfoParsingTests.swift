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


    func testParseMalformedThrows() {
        XCTAssertThrowsError(try parse(data(#"{"foo":"bar"}"#), as: .ipinfo))
    }

    func testParseRejectsInvalidIPValue() {
        // 200-OK body that decodes but whose IP is garbage (captive portal / error page).
        XCTAssertThrowsError(try parseAddress(data(#"{"ip":"not-an-ip"}"#), as: .ipifyJSON))
        XCTAssertThrowsError(try parse(data(#"{"ip":"login.example.com","city":"X","country":"US"}"#), as: .ipinfo))
        XCTAssertThrowsError(try parseAddress(data(#"{"ip":""}"#), as: .ipifyJSON))
    }

    func testParseAcceptsIPv6() throws {
        XCTAssertEqual(try parseAddress(data(#"{"ip":"2001:db8::1"}"#), as: .ipifyJSON), "2001:db8::1")
        XCTAssertEqual(try parse(data(#"{"ip":"2001:db8::1","country":"DE"}"#), as: .ipinfo).ip, "2001:db8::1")
    }

    func testCleanISP() {
        XCTAssertEqual(cleanISP("AS13335 Cloudflare, Inc."), "Cloudflare, Inc.")
        XCTAssertEqual(cleanISP("Cloudflare, Inc."), "Cloudflare, Inc.")
        XCTAssertNil(cleanISP(nil))
        XCTAssertNil(cleanISP(""))
    }

    func testParseIPWhoIs() throws {
        let json = """
        {"ip":"8.8.8.8","success":true,"country":"United States","country_code":"US","region":"California","city":"Mountain View","connection":{"asn":15169,"org":"Google LLC","isp":"Google LLC"}}
        """
        let info = try parse(data(json), as: .ipwhois)
        XCTAssertEqual(info, IPInfo(
            ip: "8.8.8.8", city: "Mountain View", region: "California",
            countryCode: "US", countryName: "United States", isp: "Google LLC"
        ))
    }

    func testParseIPWhoIsErrorBodyThrows() {
        // ipwho.is answers errors with HTTP 200 + success:false.
        XCTAssertThrowsError(try parse(data(#"{"ip":"8.8.8.8","success":false,"message":"Invalid IP address"}"#), as: .ipwhois))
    }

    func testParseAddressPlainText() throws {
        XCTAssertEqual(try parseAddress(data("203.0.113.42\n"), as: .plainText), "203.0.113.42")
        XCTAssertEqual(try parseAddress(data("  2001:db8::1 "), as: .plainText), "2001:db8::1")
        XCTAssertThrowsError(try parseAddress(data("<html>portal</html>"), as: .plainText))
        XCTAssertThrowsError(try parseAddress(data(""), as: .plainText))
    }

    func testParseAddressIpify() throws {
        XCTAssertEqual(try parseAddress(data(#"{"ip":"203.0.113.42"}"#), as: .ipifyJSON), "203.0.113.42")
        XCTAssertThrowsError(try parseAddress(data(#"{"ip":"nope"}"#), as: .ipifyJSON))
        XCTAssertThrowsError(try parseAddress(data(#"{"foo":"bar"}"#), as: .ipifyJSON))
    }

    func testIPInfoRoundTripsThroughJSON() throws {
        let info = IPInfo(ip: "1.2.3.4", city: "X", region: "Y", countryCode: "US", countryName: "United States", isp: "Foo")
        let decoded = try JSONDecoder().decode(IPInfo.self, from: JSONEncoder().encode(info))
        XCTAssertEqual(decoded, info)
    }
}
