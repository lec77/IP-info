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
        XCTAssertEqual(Config.offlineConfirmations, 2)
        XCTAssertEqual(Config.offlineRecheckDelay, 2)
    }

    // Offline hysteresis: require `confirmAfter` consecutive failures before reporting.
    func testConfirmSuccessReportsAndResets() {
        let r = confirmOutcome(.success(IPInfo(ip: "1.1.1.1")), failureStreak: 5, confirmAfter: 2)
        XCTAssertTrue(r.report)
        XCTAssertEqual(r.failureStreak, 0)
    }

    func testConfirmFirstFailureHeld() {
        let r = confirmOutcome(.offline, failureStreak: 0, confirmAfter: 2)
        XCTAssertFalse(r.report)
        XCTAssertEqual(r.failureStreak, 1)
    }

    func testConfirmSecondFailureConfirms() {
        let r = confirmOutcome(.offline, failureStreak: 1, confirmAfter: 2)
        XCTAssertTrue(r.report)
        XCTAssertEqual(r.failureStreak, 2)
    }

    func testConfirmKeepsReportingAfterThreshold() {
        let r = confirmOutcome(.lookupFailed, failureStreak: 2, confirmAfter: 2)
        XCTAssertTrue(r.report)
        XCTAssertEqual(r.failureStreak, 3)
    }

    func testConfirmAfterOneIsImmediate() {
        let r = confirmOutcome(.offline, failureStreak: 0, confirmAfter: 1)
        XCTAssertTrue(r.report)
        XCTAssertEqual(r.failureStreak, 1)
    }

    func testLookupFailedCountsAsFailure() {
        let r = confirmOutcome(.lookupFailed, failureStreak: 0, confirmAfter: 2)
        XCTAssertFalse(r.report)
        XCTAssertEqual(r.failureStreak, 1)
    }
}
