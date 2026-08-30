import XCTest
@testable import ExitIPCore

final class ConnectivityTests: XCTestCase {
    private let snap = ExitSnapshot(primary: IPInfo(ip: "1.2.3.4", countryCode: "US"))

    func testUnreachableIsOffline() {
        XCTAssertEqual(combinedOutcome(probe: .unreachable, fetched: nil), .failure(.offline))
        // Unreachable probe wins even if (defensively) a snapshot is passed.
        XCTAssertEqual(combinedOutcome(probe: .unreachable, fetched: snap), .failure(.offline))
    }

    func testCaptivePortalWinsOverFetch() {
        XCTAssertEqual(combinedOutcome(probe: .captivePortal, fetched: nil), .failure(.captivePortal))
        XCTAssertEqual(combinedOutcome(probe: .captivePortal, fetched: snap), .failure(.captivePortal))
    }

    func testReachableWithSnapshotIsSuccess() {
        XCTAssertEqual(combinedOutcome(probe: .reachable, fetched: snap), .success(snap))
    }

    func testReachableWithoutSnapshotIsLookupFailed() {
        XCTAssertEqual(combinedOutcome(probe: .reachable, fetched: nil), .failure(.lookupFailed))
    }

    // Probe classification: only the exact expected status counts as reachable.
    func testProbeVerdict() {
        XCTAssertEqual(probeVerdict(statusCode: 204), .reachable)
        XCTAssertEqual(probeVerdict(statusCode: nil), .unreachable)
        // Portal bouncing to its login page (redirects are not followed).
        XCTAssertEqual(probeVerdict(statusCode: 302), .captivePortal)
        XCTAssertEqual(probeVerdict(statusCode: 307), .captivePortal)
        // Portal serving its own page in place of the probe.
        XCTAssertEqual(probeVerdict(statusCode: 200), .captivePortal)
        XCTAssertEqual(probeVerdict(statusCode: 503), .captivePortal)
        XCTAssertEqual(probeVerdict(statusCode: 200, expected: 200), .reachable)
    }

    func testOnlyCaptivePortalIsActionable() {
        XCTAssertTrue(FailureReason.captivePortal.isActionable)
        XCTAssertFalse(FailureReason.offline.isActionable)
        XCTAssertFalse(FailureReason.lookupFailed.isActionable)
    }

    func testProbeConfig() {
        // HTTPS primary (some local filters block plain HTTP); plain-HTTP fallback is
        // what captive portals can actually intercept.
        XCTAssertEqual(Config.probeURL.absoluteString, "https://www.gstatic.com/generate_204")
        XCTAssertEqual(Config.captiveProbeURL.absoluteString, "http://www.gstatic.com/generate_204")
        XCTAssertEqual(Config.probeExpectedStatus, 204)
        XCTAssertEqual(Config.captivePortalSignInURL.scheme, "http")
        XCTAssertEqual(Config.probeTimeout, 5)
        XCTAssertEqual(Config.offlineConfirmations, 2)
        XCTAssertEqual(Config.offlineRecheckDelay, 2)
    }

    // Offline hysteresis: require `confirmAfter` consecutive failures before reporting.
    func testConfirmSuccessReportsAndResets() {
        let r = confirmOutcome(.success(snap), failureStreak: 5, confirmAfter: 2)
        XCTAssertTrue(r.report)
        XCTAssertEqual(r.failureStreak, 0)
    }

    func testConfirmFirstFailureHeld() {
        let r = confirmOutcome(.failure(.offline), failureStreak: 0, confirmAfter: 2)
        XCTAssertFalse(r.report)
        XCTAssertEqual(r.failureStreak, 1)
    }

    func testConfirmSecondFailureConfirms() {
        let r = confirmOutcome(.failure(.offline), failureStreak: 1, confirmAfter: 2)
        XCTAssertTrue(r.report)
        XCTAssertEqual(r.failureStreak, 2)
    }

    func testConfirmKeepsReportingAfterThreshold() {
        let r = confirmOutcome(.failure(.lookupFailed), failureStreak: 2, confirmAfter: 2)
        XCTAssertTrue(r.report)
        XCTAssertEqual(r.failureStreak, 3)
    }

    func testConfirmAfterOneIsImmediate() {
        let r = confirmOutcome(.failure(.offline), failureStreak: 0, confirmAfter: 1)
        XCTAssertTrue(r.report)
        XCTAssertEqual(r.failureStreak, 1)
    }

    func testEveryFailureCountsTowardsTheStreak() {
        for reason in [FailureReason.offline, .captivePortal, .lookupFailed] {
            let r = confirmOutcome(.failure(reason), failureStreak: 0, confirmAfter: 2)
            XCTAssertFalse(r.report)
            XCTAssertEqual(r.failureStreak, 1)
        }
    }
}
