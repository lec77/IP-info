import XCTest
@testable import ExitIPCore

final class ExitComparisonTests: XCTestCase {
    private let ip = IPInfo(ip: "192.0.2.1")

    func testFreshComparisonAndUnknownState() {
        let model = ExitIPModel(phase: .ok, lastGood: ExitSnapshot(primary: ip))
        XCTAssertEqual(exitComparisonText(model: model, onTunnel: true, direct: ip), "Detected exit matches direct connection")
        XCTAssertEqual(exitComparisonText(model: model, onTunnel: true, direct: IPInfo(ip: "203.0.113.1")), "Detected exit differs from direct connection")
        XCTAssertEqual(exitComparisonText(model: model, onTunnel: true, direct: nil), "Direct exit unknown")
        XCTAssertEqual(exitComparisonText(model: model, onTunnel: false, direct: ip), "No tunnel detected")
    }

    func testFailureNeverPresentsOldAddressesAsCurrentComparison() {
        let model = ExitIPModel(phase: .failed(.offline), lastGood: ExitSnapshot(primary: ip))
        XCTAssertEqual(exitComparisonText(model: model, onTunnel: true, direct: IPInfo(ip: "203.0.113.1")), "Offline")
        XCTAssertEqual(exitComparisonText(model: ExitIPModel(), onTunnel: true, direct: nil), "Waiting for first check")
    }
}
