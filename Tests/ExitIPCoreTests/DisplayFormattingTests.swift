import XCTest
@testable import ExitIPCore

final class DisplayFormattingTests: XCTestCase {
    private let full = IPInfo(ip: "1.2.3.4", city: "San Jose", region: "California",
                             countryCode: "US", countryName: "United States", isp: "Cloudflare, Inc.")

    func testTitleInitial() {
        XCTAssertEqual(menuBarTitle(for: ExitIPModel()), "…")
    }

    func testTitleOkFlagAndCity() {
        XCTAssertEqual(menuBarTitle(for: ExitIPModel(phase: .ok, lastGoodIP: full)), "🇺🇸 San Jose")
    }

    func testTitleOkFlagNoCity() {
        let info = IPInfo(ip: "1.2.3.4", countryCode: "US")
        XCTAssertEqual(menuBarTitle(for: ExitIPModel(phase: .ok, lastGoodIP: info)), "🇺🇸")
    }

    func testTitleOkCityNoFlag() {
        let info = IPInfo(ip: "1.2.3.4", city: "San Jose")
        XCTAssertEqual(menuBarTitle(for: ExitIPModel(phase: .ok, lastGoodIP: info)), "San Jose")
    }

    func testTitleOkNoFlagNoCityFallsBackToIP() {
        let info = IPInfo(ip: "1.2.3.4")
        XCTAssertEqual(menuBarTitle(for: ExitIPModel(phase: .ok, lastGoodIP: info)), "1.2.3.4")
    }

    func testTitleOffline() {
        XCTAssertEqual(menuBarTitle(for: ExitIPModel(phase: .failed(.offline), lastGoodIP: full)), "⚠︎ offline")
    }

    func testTitleLookupFailedWithLastKnown() {
        XCTAssertEqual(menuBarTitle(for: ExitIPModel(phase: .failed(.lookupFailed), lastGoodIP: full)), "⚠︎ 🇺🇸 San Jose")
    }

    func testTitleLookupFailedNoLastKnown() {
        XCTAssertEqual(menuBarTitle(for: ExitIPModel(phase: .failed(.lookupFailed), lastGoodIP: nil)), "⚠︎")
    }

    func testLines() {
        XCTAssertEqual(ipLine(for: full), "IP: 1.2.3.4")
        XCTAssertEqual(locationLine(for: full), "Location: San Jose, United States")
        XCTAssertEqual(ispLine(for: full), "ISP: Cloudflare, Inc.")
    }

    func testLinesOmittedWhenMissing() {
        let info = IPInfo(ip: "1.2.3.4")
        XCTAssertNil(locationLine(for: info))
        XCTAssertNil(ispLine(for: info))
    }

    func testLastCheckedText() {
        XCTAssertEqual(lastCheckedText(secondsAgo: 3), "Last checked: just now")
        XCTAssertEqual(lastCheckedText(secondsAgo: 12), "Last checked: 12s ago")
        XCTAssertEqual(lastCheckedText(secondsAgo: 90), "Last checked: 1m ago")
        XCTAssertEqual(lastCheckedText(secondsAgo: 7200), "Last checked: 2h ago")
    }
}
