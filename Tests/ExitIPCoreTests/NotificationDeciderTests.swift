import XCTest
@testable import ExitIPCore

final class NotificationDeciderTests: XCTestCase {
    private let a = IPInfo(ip: "1.1.1.1", countryCode: "US")
    private let b = IPInfo(ip: "2.2.2.2", countryCode: "DE")
    private func snap(_ i: IPInfo) -> ExitSnapshot { ExitSnapshot(primary: i) }

    func testInitialSuccessIsSilent() {
        let (model, notes) = reduce(ExitIPModel(), applying: .success(snap(a)))
        XCTAssertEqual(model, ExitIPModel(phase: .ok, lastGood: snap(a)))
        XCTAssertEqual(notes, [])
    }

    func testIPChangeNotifies() {
        let prev = ExitIPModel(phase: .ok, lastGood: snap(a))
        let (model, notes) = reduce(prev, applying: .success(snap(b)))
        XCTAssertEqual(model, ExitIPModel(phase: .ok, lastGood: snap(b)))
        XCTAssertEqual(notes, [AppNotification(title: "Exit IP changed", body: "1.1.1.1 (US) → 2.2.2.2 (DE)")])
    }

    func testIPChangeWithMissingCountryCode() {
        let noCC = IPInfo(ip: "1.1.1.1")
        let prev = ExitIPModel(phase: .ok, lastGood: snap(noCC))
        let (_, notes) = reduce(prev, applying: .success(snap(b)))
        XCTAssertEqual(notes, [AppNotification(title: "Exit IP changed", body: "1.1.1.1 → 2.2.2.2 (DE)")])
    }

    func testSameIPNoNotify() {
        let prev = ExitIPModel(phase: .ok, lastGood: snap(a))
        XCTAssertEqual(reduce(prev, applying: .success(snap(a))).notifications, [])
    }

    func testRestoredAfterFailure() {
        let prev = ExitIPModel(phase: .failed(.lookupFailed), lastGood: snap(a))
        let (model, notes) = reduce(prev, applying: .success(snap(a)))
        XCTAssertEqual(model, ExitIPModel(phase: .ok, lastGood: snap(a)))
        XCTAssertEqual(notes, [AppNotification(title: "Exit IP restored", body: "1.1.1.1 (unchanged)")])
    }

    func testOfflineFromOkNotifies() {
        let prev = ExitIPModel(phase: .ok, lastGood: snap(a))
        let (model, notes) = reduce(prev, applying: .failure(.offline))
        XCTAssertEqual(model, ExitIPModel(phase: .failed(.offline), lastGood: snap(a)))
        XCTAssertEqual(notes, [AppNotification(title: "Exit IP unavailable", body: "No network connection.")])
    }

    func testLookupFailedFromOkNotifies() {
        let prev = ExitIPModel(phase: .ok, lastGood: snap(a))
        let (model, notes) = reduce(prev, applying: .failure(.lookupFailed))
        XCTAssertEqual(notes, [AppNotification(title: "Exit IP unavailable", body: "Could not reach IP lookup service.")])
        XCTAssertEqual(model, ExitIPModel(phase: .failed(.lookupFailed), lastGood: snap(a)))
    }

    func testNoRepeatWhileFailed() {
        let prev = ExitIPModel(phase: .failed(.offline), lastGood: snap(a))
        let (model, notes) = reduce(prev, applying: .failure(.offline))
        XCTAssertEqual(notes, [])
        XCTAssertEqual(model, ExitIPModel(phase: .failed(.offline), lastGood: snap(a)))
        // Nor between two non-actionable reasons.
        XCTAssertEqual(reduce(prev, applying: .failure(.lookupFailed)).notifications, [])
    }

    func testSilentInitialFailure() {
        let (model, notes) = reduce(ExitIPModel(), applying: .failure(.offline))
        XCTAssertEqual(model, ExitIPModel(phase: .failed(.offline), lastGood: nil))
        XCTAssertEqual(notes, [])
    }

    func testCaptivePortalFromOkNotifies() {
        let prev = ExitIPModel(phase: .ok, lastGood: snap(a))
        let (model, notes) = reduce(prev, applying: .failure(.captivePortal))
        XCTAssertEqual(model, ExitIPModel(phase: .failed(.captivePortal), lastGood: snap(a)))
        XCTAssertEqual(notes, [AppNotification(title: "Exit IP unavailable", body: "Captive portal detected — open a browser to sign in.")])
    }

    func testActionableFailureStillNotifiesWhileFailed() {
        // Landing on a portal is actionable (sign in), so it breaks the no-repeat-while-failed rule.
        let prev = ExitIPModel(phase: .failed(.offline), lastGood: snap(a))
        let notes = reduce(prev, applying: .failure(.captivePortal)).notifications
        XCTAssertEqual(notes.first?.body, "Captive portal detected — open a browser to sign in.")
    }

    func testActionableFailureDoesNotRepeat() {
        let prev = ExitIPModel(phase: .failed(.captivePortal), lastGood: snap(a))
        XCTAssertEqual(reduce(prev, applying: .failure(.captivePortal)).notifications, [])
        // Portal -> plain offline is not worth another alert either.
        XCTAssertEqual(reduce(prev, applying: .failure(.offline)).notifications, [])
    }

    func testIPv6OnlyChangeIsSilent() {
        let v6a = ExitSnapshot(primary: a, ipv6: IPInfo(ip: "2001:db8::1"))
        let v6b = ExitSnapshot(primary: a, ipv6: IPInfo(ip: "2001:db8::2"))
        let (model, notes) = reduce(ExitIPModel(phase: .ok, lastGood: v6a), applying: .success(v6b))
        XCTAssertEqual(notes, [])
        XCTAssertEqual(model.lastGood, v6b)
    }

    // MARK: warnings ride along with the reading

    func testSuccessAssessesWarningsAndNotifies() {
        let ctx = WarningContext(expectedCountryCode: "DE")
        let (model, notes) = reduce(ExitIPModel(), applying: .success(snap(a)), context: ctx)
        XCTAssertEqual(model.warnings, [.unexpectedCountry])
        XCTAssertEqual(model.activeWarnings, [.unexpectedCountry])
        XCTAssertEqual(notes.map(\.title), ["Unexpected exit"]) // even on the (otherwise silent) first reading
    }

    func testChangeAndWarningNotificationsAreOrdered() {
        let ctx = WarningContext(expectedCountryCode: "US")
        let prev = ExitIPModel(phase: .ok, lastGood: snap(a))
        let notes = reduce(prev, applying: .success(snap(b)), context: ctx).notifications
        XCTAssertEqual(notes.map(\.title), ["Exit IP changed", "Unexpected exit"])
    }

    func testWarningsSurviveFailuresWithoutReAlerting() {
        let ctx = WarningContext(expectedCountryCode: "DE")
        let warned = ExitIPModel(phase: .ok, lastGood: snap(a), warnings: [.unexpectedCountry])
        let (down, downNotes) = reduce(warned, applying: .failure(.offline), context: ctx)
        XCTAssertEqual(down.warnings, [.unexpectedCountry])
        XCTAssertEqual(down.activeWarnings, []) // not shown while offline
        XCTAssertEqual(downNotes.map(\.title), ["Exit IP unavailable"])
        let (up, upNotes) = reduce(down, applying: .success(snap(a)), context: ctx)
        XCTAssertEqual(up.activeWarnings, [.unexpectedCountry])
        XCTAssertEqual(upNotes.map(\.title), ["Exit IP restored"]) // same warning: no second alert
    }

    func testReassessOnContextChange() {
        let ok = ExitIPModel(phase: .ok, lastGood: snap(a))
        let (pinned, pinnedNotes) = reassess(ok, context: WarningContext(expectedCountryCode: "DE"))
        XCTAssertEqual(pinned.warnings, [.unexpectedCountry])
        XCTAssertEqual(pinnedNotes.map(\.title), ["Unexpected exit"])
        let (cleared, clearedNotes) = reassess(pinned, context: WarningContext())
        XCTAssertEqual(cleared.warnings, [])
        XCTAssertEqual(clearedNotes.map(\.title), ["Exit OK"])
    }

    func testReassessIsNoOpUnlessOk() {
        let down = ExitIPModel(phase: .failed(.offline), lastGood: snap(a), warnings: [.ipv6Mismatch])
        let (model, notes) = reassess(down, context: WarningContext(expectedCountryCode: "DE"))
        XCTAssertEqual(model, down)
        XCTAssertEqual(notes, [])
        XCTAssertEqual(reassess(ExitIPModel(), context: WarningContext(expectedCountryCode: "DE")).notifications, [])
    }
}
