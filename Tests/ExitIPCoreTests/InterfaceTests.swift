import XCTest
import Network
@testable import ExitIPCore

final class InterfaceTests: XCTestCase {
    func testStandardTypesMapDirectly() {
        XCTAssertEqual(interfaceKind(name: "en0", type: .wifi), .wifi)
        XCTAssertEqual(interfaceKind(name: "en5", type: .wiredEthernet), .wired)
        XCTAssertEqual(interfaceKind(name: "pdp_ip0", type: .cellular), .cellular)
        XCTAssertEqual(interfaceKind(name: "lo0", type: .loopback), .loopback)
    }

    func testTunnelNamesAreRecognised() {
        for name in ["utun3", "ipsec0", "ppp0", "tun0", "tap1", "wg0"] {
            XCTAssertEqual(interfaceKind(name: name, type: .other), .tunnel, name)
        }
        XCTAssertEqual(interfaceKind(name: "bridge100", type: .other), .other)
        XCTAssertEqual(interfaceKind(name: "awdl0", type: .other), .other)
    }

    func testIPv6LookupSkippedOnlyWithoutRouteAndOffTunnel() {
        let wifi = ActiveInterface(name: "en0", kind: .wifi)
        let tunnel = ActiveInterface(name: "utun4", kind: .tunnel)
        XCTAssertTrue(shouldLookupIPv6(pathSupportsIPv6: true, interface: wifi))
        XCTAssertFalse(shouldLookupIPv6(pathSupportsIPv6: false, interface: wifi))
        XCTAssertFalse(shouldLookupIPv6(pathSupportsIPv6: false, interface: nil))
        // A tunnel without IPv6 is exactly the leaking setup: always check.
        XCTAssertTrue(shouldLookupIPv6(pathSupportsIPv6: false, interface: tunnel))
    }

    func testInterfaceLine() {
        XCTAssertEqual(interfaceLine(ActiveInterface(name: "en0", kind: .wifi)), "Via: Wi-Fi (en0)")
        XCTAssertEqual(interfaceLine(ActiveInterface(name: "en5", kind: .wired)), "Via: Ethernet (en5)")
        XCTAssertEqual(interfaceLine(ActiveInterface(name: "utun4", kind: .tunnel)), "Via: VPN tunnel (utun4)")
        XCTAssertEqual(interfaceLine(nil), "Via: —")
    }
}
