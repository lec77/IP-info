import XCTest
@testable import ExitIPCore

final class NotificationDeciderTests: XCTestCase {
    private let a = IPInfo(ip: "1.1.1.1", countryCode: "US")
    private let b = IPInfo(ip: "2.2.2.2", countryCode: "DE")

    func testInitialSuccessIsSilent() {
        let (model, note) = reduce(ExitIPModel(), applying: .success(a))
        XCTAssertEqual(model, ExitIPModel(phase: .ok, lastGoodIP: a))
        XCTAssertNil(note)
    }

    func testIPChangeNotifies() {
        let prev = ExitIPModel(phase: .ok, lastGoodIP: a)
        let (model, note) = reduce(prev, applying: .success(b))
        XCTAssertEqual(model, ExitIPModel(phase: .ok, lastGoodIP: b))
        XCTAssertEqual(note, AppNotification(title: "Exit IP changed", body: "1.1.1.1 (US) → 2.2.2.2 (DE)"))
    }

    func testIPChangeWithMissingCountryCode() {
        let noCC = IPInfo(ip: "1.1.1.1")
        let prev = ExitIPModel(phase: .ok, lastGoodIP: noCC)
        let (_, note) = reduce(prev, applying: .success(b))
        XCTAssertEqual(note, AppNotification(title: "Exit IP changed", body: "1.1.1.1 → 2.2.2.2 (DE)"))
    }

    func testSameIPNoNotify() {
        let prev = ExitIPModel(phase: .ok, lastGoodIP: a)
        let (_, note) = reduce(prev, applying: .success(a))
        XCTAssertNil(note)
    }

    func testRestoredAfterFailure() {
        let prev = ExitIPModel(phase: .failed(.lookupFailed), lastGoodIP: a)
        let (model, note) = reduce(prev, applying: .success(a))
        XCTAssertEqual(model, ExitIPModel(phase: .ok, lastGoodIP: a))
        XCTAssertEqual(note, AppNotification(title: "Exit IP restored", body: "1.1.1.1 (unchanged)"))
    }

    func testOfflineFromOkNotifies() {
        let prev = ExitIPModel(phase: .ok, lastGoodIP: a)
        let (model, note) = reduce(prev, applying: .offline)
        XCTAssertEqual(model, ExitIPModel(phase: .failed(.offline), lastGoodIP: a))
        XCTAssertEqual(note, AppNotification(title: "Exit IP unavailable", body: "No network connection."))
    }

    func testLookupFailedFromOkNotifies() {
        let prev = ExitIPModel(phase: .ok, lastGoodIP: a)
        let (model, note) = reduce(prev, applying: .lookupFailed)
        XCTAssertEqual(note, AppNotification(title: "Exit IP unavailable", body: "Could not reach IP lookup service."))
        XCTAssertEqual(model, ExitIPModel(phase: .failed(.lookupFailed), lastGoodIP: a))
    }

    func testNoRepeatWhileFailed() {
        let prev = ExitIPModel(phase: .failed(.offline), lastGoodIP: a)
        let (model, note) = reduce(prev, applying: .offline)
        XCTAssertNil(note)
        XCTAssertEqual(model, ExitIPModel(phase: .failed(.offline), lastGoodIP: a))
    }

    func testSilentInitialFailure() {
        let (model, note) = reduce(ExitIPModel(), applying: .offline)
        XCTAssertEqual(model, ExitIPModel(phase: .failed(.offline), lastGoodIP: nil))
        XCTAssertNil(note)
    }
}
