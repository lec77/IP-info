import XCTest
@testable import ExitIPCore

final class WarningsTests: XCTestCase {
    private let de = IPInfo(ip: "2.2.2.2", city: "Berlin", countryCode: "DE", isp: "VPN GmbH")
    private let us = IPInfo(ip: "1.1.1.1", city: "San Jose", countryCode: "US", isp: "Comcast")
    private let usV6 = IPInfo(ip: "2001:db8::1", countryCode: "US", isp: "Comcast")
    private let deV6 = IPInfo(ip: "2001:db8::2", countryCode: "DE", isp: "VPN GmbH")
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: expected country

    func testNoExpectationNoWarning() {
        XCTAssertEqual(assessWarnings(ExitSnapshot(primary: us), context: WarningContext()), [])
    }

    func testMatchingExpectationIsQuiet() {
        let ctx = WarningContext(expectedCountryCode: "de")
        XCTAssertEqual(assessWarnings(ExitSnapshot(primary: de), context: ctx), [])
    }

    func testMismatchWarns() {
        let ctx = WarningContext(expectedCountryCode: "DE")
        XCTAssertEqual(assessWarnings(ExitSnapshot(primary: us), context: ctx), [.unexpectedCountry])
    }

    func testUnknownGeoIsNotAMismatch() {
        let ctx = WarningContext(expectedCountryCode: "DE")
        XCTAssertEqual(assessWarnings(ExitSnapshot(primary: IPInfo(ip: "1.1.1.1")), context: ctx), [])
    }

    // MARK: IPv6

    func testIPv6SameCountryAndISPIsQuiet() {
        let ctx = WarningContext(onTunnel: true)
        XCTAssertEqual(assessWarnings(ExitSnapshot(primary: de, ipv6: deV6), context: ctx), [])
    }

    func testIPv6DifferentCountryWarnsEvenOffTunnel() {
        XCTAssertEqual(assessWarnings(ExitSnapshot(primary: de, ipv6: usV6), context: WarningContext()), [.ipv6Mismatch])
    }

    func testIPv6DifferentISPWarnsOnlyOnTunnel() {
        let v6 = IPInfo(ip: "2001:db8::3", countryCode: "DE", isp: "Home ISP")
        XCTAssertEqual(assessWarnings(ExitSnapshot(primary: de, ipv6: v6), context: WarningContext(onTunnel: false)), [])
        XCTAssertEqual(assessWarnings(ExitSnapshot(primary: de, ipv6: v6), context: WarningContext(onTunnel: true)), [.ipv6Mismatch])
    }

    func testIPv6WithUnknownGeoIsQuiet() {
        let ctx = WarningContext(onTunnel: true)
        XCTAssertEqual(assessWarnings(ExitSnapshot(primary: de, ipv6: IPInfo(ip: "2001:db8::9")), context: ctx), [])
    }

    // MARK: tunnel vs home

    func testTunnelExitIsHomeByISP() {
        let ctx = WarningContext(onTunnel: true, homeExit: IPInfo(ip: "1.1.1.9", isp: "comcast"))
        XCTAssertEqual(assessWarnings(ExitSnapshot(primary: us), context: ctx), [.tunnelExitIsHome])
    }

    func testTunnelExitIsHomeByAddress() {
        let ctx = WarningContext(onTunnel: true, homeExit: IPInfo(ip: "1.1.1.1"))
        XCTAssertEqual(assessWarnings(ExitSnapshot(primary: us), context: ctx), [.tunnelExitIsHome])
    }

    func testTunnelWithDifferentExitIsQuiet() {
        let ctx = WarningContext(onTunnel: true, homeExit: us)
        XCTAssertEqual(assessWarnings(ExitSnapshot(primary: de), context: ctx), [])
    }

    func testHomeExitIgnoredOffTunnel() {
        let ctx = WarningContext(onTunnel: false, homeExit: us)
        XCTAssertEqual(assessWarnings(ExitSnapshot(primary: us), context: ctx), [])
    }

    func testIsSameExit() {
        XCTAssertTrue(isSameExit(IPInfo(ip: "1.1.1.1"), IPInfo(ip: "1.1.1.1", isp: "x")))
        XCTAssertTrue(isSameExit(IPInfo(ip: "1.1.1.1", isp: "Comcast"), IPInfo(ip: "2.2.2.2", isp: " comcast ")))
        XCTAssertFalse(isSameExit(IPInfo(ip: "1.1.1.1", isp: "A"), IPInfo(ip: "2.2.2.2", isp: "B")))
        XCTAssertFalse(isSameExit(IPInfo(ip: "1.1.1.1"), IPInfo(ip: "2.2.2.2", isp: "B")))
    }

    func testAllWarningsTogetherInStableOrder() {
        let ctx = WarningContext(expectedCountryCode: "DE", onTunnel: true, homeExit: us)
        XCTAssertEqual(assessWarnings(ExitSnapshot(primary: us, ipv6: deV6), context: ctx),
                       [.unexpectedCountry, .ipv6Mismatch, .tunnelExitIsHome])
    }

    // MARK: remembering home

    func testHomeExitTakenFromNonTunnelInterface() {
        let wifi = ActiveInterface(name: "en0", kind: .wifi)
        XCTAssertEqual(homeExit(after: ExitSnapshot(primary: us), via: wifi, previous: nil), us)
        XCTAssertEqual(homeExit(after: ExitSnapshot(primary: de), via: wifi, previous: us), de)
    }

    func testHomeExitKeptOnTunnelOrUnknownInterface() {
        let tunnel = ActiveInterface(name: "utun4", kind: .tunnel)
        XCTAssertEqual(homeExit(after: ExitSnapshot(primary: de), via: tunnel, previous: us), us)
        XCTAssertNil(homeExit(after: ExitSnapshot(primary: de), via: tunnel, previous: nil))
        XCTAssertEqual(homeExit(after: ExitSnapshot(primary: de), via: nil, previous: us), us)
    }

    // MARK: pin choices

    func testExpectedCountryChoices() {
        let history = [
            IPChangeEvent(date: t0, from: nil, to: IPInfo(ip: "3.3.3.3", countryCode: "jp")),
            IPChangeEvent(date: t0, from: nil, to: IPInfo(ip: "4.4.4.4", countryCode: "US")),
            IPChangeEvent(date: t0, from: nil, to: IPInfo(ip: "5.5.5.5")),          // no geo: skipped
            IPChangeEvent(date: t0, from: nil, to: IPInfo(ip: "6.6.6.6", countryCode: "bad")), // invalid: skipped
        ]
        // Deduped (US appears twice), normalised, sorted by display name.
        XCTAssertEqual(expectedCountryChoices(current: "us", pinned: "DE", history: history), ["DE", "JP", "US"])
        XCTAssertEqual(expectedCountryChoices(current: nil, pinned: nil, history: []), [])
    }

    // MARK: notifications

    func testNewWarningNotifies() {
        let notes = warningNotifications(previous: [], current: [.unexpectedCountry],
                                         snapshot: ExitSnapshot(primary: us), expectedCountryCode: "DE")
        XCTAssertEqual(notes, [AppNotification(title: "Unexpected exit",
                                               body: "Exit is 🇺🇸 United States — expected 🇩🇪 Germany.")])
    }

    func testPersistingWarningIsSilent() {
        XCTAssertEqual(warningNotifications(previous: [.unexpectedCountry], current: [.unexpectedCountry],
                                            snapshot: ExitSnapshot(primary: us), expectedCountryCode: "DE"), [])
    }

    func testAllClearNotifiesOnce() {
        let notes = warningNotifications(previous: [.tunnelExitIsHome], current: [],
                                         snapshot: ExitSnapshot(primary: de), expectedCountryCode: nil)
        XCTAssertEqual(notes, [AppNotification(title: "Exit OK", body: "All exit checks pass again: 🇩🇪 Berlin · 2.2.2.2")])
        XCTAssertEqual(warningNotifications(previous: [], current: [], snapshot: ExitSnapshot(primary: de), expectedCountryCode: nil), [])
    }

    func testLeakNotificationTexts() {
        let v6 = warningNotifications(previous: [], current: [.ipv6Mismatch],
                                      snapshot: ExitSnapshot(primary: de, ipv6: usV6), expectedCountryCode: nil)
        XCTAssertEqual(v6, [AppNotification(title: "Possible IPv6 leak",
                                            body: "IPv6 traffic exits via 🇺🇸 Comcast (2001:db8::1), not through your IPv4 exit.")])
        let home = warningNotifications(previous: [], current: [.tunnelExitIsHome],
                                        snapshot: ExitSnapshot(primary: us), expectedCountryCode: nil)
        XCTAssertEqual(home, [AppNotification(title: "Possible VPN leak",
                                              body: "A tunnel is up, but the exit is your usual ISP (Comcast).")])
        let homeNoISP = warningNotifications(previous: [], current: [.tunnelExitIsHome],
                                             snapshot: ExitSnapshot(primary: IPInfo(ip: "1.1.1.1")), expectedCountryCode: nil)
        XCTAssertEqual(homeNoISP.first?.body, "A tunnel is up, but the exit is your usual ISP.")
    }

    func testWarningLines() {
        XCTAssertEqual(warningLine(.unexpectedCountry, snapshot: ExitSnapshot(primary: us), expectedCountryCode: "DE"),
                       "⛔ Exit is 🇺🇸 United States, expected 🇩🇪 Germany")
        XCTAssertEqual(warningLine(.ipv6Mismatch, snapshot: ExitSnapshot(primary: de, ipv6: usV6), expectedCountryCode: nil),
                       "⚠︎ IPv6 exits via 🇺🇸 Comcast — possible leak")
        XCTAssertEqual(warningLine(.ipv6Mismatch, snapshot: ExitSnapshot(primary: de, ipv6: IPInfo(ip: "2001:db8::1")), expectedCountryCode: nil),
                       "⚠︎ IPv6 exits via 2001:db8::1 — possible leak")
        XCTAssertEqual(warningLine(.tunnelExitIsHome, snapshot: ExitSnapshot(primary: us), expectedCountryCode: nil),
                       "⚠︎ Tunnel up, but exit is your usual ISP (Comcast)")
        XCTAssertEqual(warningLine(.tunnelExitIsHome, snapshot: ExitSnapshot(primary: IPInfo(ip: "1.1.1.1")), expectedCountryCode: nil),
                       "⚠︎ Tunnel up, but exit is your usual ISP")
    }
}
