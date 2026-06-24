import XCTest
@testable import ExitIPCore

final class CountryFlagTests: XCTestCase {
    func testFlagFromUppercaseCode() {
        XCTAssertEqual(flag(forCountryCode: "US"), "🇺🇸")
        XCTAssertEqual(flag(forCountryCode: "DE"), "🇩🇪")
    }

    func testFlagAcceptsLowercase() {
        XCTAssertEqual(flag(forCountryCode: "us"), "🇺🇸")
    }

    func testFlagRejectsInvalid() {
        XCTAssertNil(flag(forCountryCode: "USA"))
        XCTAssertNil(flag(forCountryCode: "U1"))
        XCTAssertNil(flag(forCountryCode: ""))
    }

    func testCountryName() {
        XCTAssertEqual(countryName(forCountryCode: "US"), "United States")
        XCTAssertEqual(countryName(forCountryCode: "DE"), "Germany")
        XCTAssertEqual(countryName(forCountryCode: "us"), "United States")
    }

    func testCountryNameInvalid() {
        XCTAssertNil(countryName(forCountryCode: "ZZ"))
        XCTAssertNil(countryName(forCountryCode: "US1"))
        XCTAssertNil(countryName(forCountryCode: "U1"))
    }
}
