import XCTest
@testable import ExitIPCore

final class ConnectivityTests: XCTestCase {
    func testUnreachableIsOffline() {
        XCTAssertEqual(combinedOutcome(reachable: false, fetchedIP: nil), .offline)
        // Unreachable probe wins even if (defensively) an IP is passed.
        XCTAssertEqual(combinedOutcome(reachable: false, fetchedIP: IPInfo(ip: "1.2.3.4")), .offline)
    }

    func testReachableWithIPIsSuccess() {
        let info = IPInfo(ip: "1.2.3.4", countryCode: "US")
        XCTAssertEqual(combinedOutcome(reachable: true, fetchedIP: info), .success(info))
    }

    func testReachableWithoutIPIsLookupFailed() {
        XCTAssertEqual(combinedOutcome(reachable: true, fetchedIP: nil), .lookupFailed)
    }

    func testProbeConfig() {
        XCTAssertEqual(Config.probeURL.absoluteString, "https://www.gstatic.com/generate_204")
        XCTAssertEqual(Config.probeTimeout, 5)
    }
}
