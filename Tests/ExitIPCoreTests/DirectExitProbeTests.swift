import XCTest
@testable import ExitIPCore

final class DirectExitProbeTests: XCTestCase {
    private let wifi = ActiveInterface(name: "en0", kind: .wifi)

    func testBoundHTTPSRequestIgnoresDNSProxyAndUserConfig() async {
        let probe = DirectExitProbe { arguments in
            XCTAssertEqual(arguments.first, "-q")
            XCTAssertTrue(arguments.contains("if!en0"))
            XCTAssertEqual(arguments[arguments.firstIndex(of: "--proxy")! + 1], "")
            XCTAssertTrue(arguments.contains("--noproxy"))
            XCTAssertTrue(arguments.contains("--max-time"))
            XCTAssertFalse(arguments.contains("--insecure"))
            XCTAssertFalse(arguments.contains("--location"))
            XCTAssertEqual(arguments.last, "https://1.1.1.1/cdn-cgi/trace")
            return Data("fl=123\nip=203.0.113.7\nwarp=off\n".utf8)
        }
        let result = await probe.measure(interface: wifi, matching: "192.0.2.1")
        XCTAssertEqual(result?.ip, "203.0.113.7")
    }

    func testIPv6UsesNumericIPv6Endpoint() async {
        let probe = DirectExitProbe { arguments in
            XCTAssertTrue(arguments.contains("--ipv6"))
            XCTAssertEqual(arguments.last, "https://[2606:4700:4700::1111]/cdn-cgi/trace")
            return Data("ip=2001:db8::7\n".utf8)
        }
        let result = await probe.measure(interface: wifi, matching: "2001:db8::1")
        XCTAssertEqual(result?.ip, "2001:db8::7")
    }

    func testFailedPrimaryFallsBackWithoutDroppingBinding() async {
        let probe = DirectExitProbe { arguments in
            XCTAssertTrue(arguments.contains("if!en0"))
            if arguments.last == "https://1.1.1.1/cdn-cgi/trace" { return nil }
            XCTAssertEqual(arguments.last, "https://1.0.0.1/cdn-cgi/trace")
            return Data("ip=203.0.113.8\n".utf8)
        }
        let result = await probe.measure(interface: wifi, matching: "192.0.2.1")
        XCTAssertEqual(result?.ip, "203.0.113.8")
    }

    func testNoPhysicalInterfaceNeverUsesDefaultRoute() async {
        let probe = DirectExitProbe { _ in
            XCTFail("Must not send unbound requests")
            return nil
        }
        for interface in [nil, ActiveInterface(name: "utun4", kind: .tunnel), ActiveInterface(name: "lo0", kind: .loopback)] {
            let result = await probe.measure(interface: interface, matching: "192.0.2.1")
            XCTAssertNil(result)
        }
    }

    func testTraceFailureFallsBackToBoundDNSAndPinnedHTTPS() async {
        let probe = DirectExitProbe { arguments in
            XCTAssertTrue(arguments.contains("if!en0"))
            XCTAssertEqual(arguments.first, "-q")
            XCTAssertTrue(arguments.contains("--noproxy"))
            if arguments.last?.contains("cdn-cgi/trace") == true { return nil }
            if arguments.last?.contains("dns.alidns.com/resolve") == true {
                XCTAssertTrue(arguments.contains("dns.alidns.com:443:223.5.5.5"))
                return Data(#"{"Status":0,"Answer":[{"type":1,"data":"203.0.113.9"}]}"#.utf8)
            }
            XCTAssertEqual(arguments.last, "https://ipv4.icanhazip.com/")
            XCTAssertTrue(arguments.contains("ipv4.icanhazip.com:443:203.0.113.9"))
            return Data("192.0.2.7\n".utf8)
        }
        let result = await probe.measure(interface: wifi, matching: "192.0.2.1")
        XCTAssertEqual(result?.ip, "192.0.2.7")
    }

    func testInvalidDNSCannotFallBackToSystemResolution() async {
        let probe = DirectExitProbe { arguments in
            if arguments.last?.contains("cdn-cgi/trace") == true { return nil }
            XCTAssertTrue(arguments.last?.contains("dns.alidns.com/resolve") == true)
            return Data(#"{"Status":0,"Answer":[{"type":1,"data":"not-an-ip"}]}"#.utf8)
        }
        let result = await probe.measure(interface: wifi, matching: "192.0.2.1")
        XCTAssertNil(result)
        XCTAssertEqual(DirectExitProbe.parseDNS(Data(#"{"Status":3}"#.utf8), ipv6: false), [])
        XCTAssertEqual(DirectExitProbe.parseDNS(Data(#"{"Status":0,"Answer":[{"type":28,"data":"2001:db8::1"}]}"#.utf8), ipv6: false), [])
    }

    func testFailureIsUnknown() async {
        let probe = DirectExitProbe { _ in nil }
        let result = await probe.measure(interface: wifi, matching: "192.0.2.1")
        XCTAssertNil(result)
    }

    func testRejectsErrorPagesMalformedDuplicateAndWrongFamilyResponses() {
        for text in ["<html>Sign in</html>", "ip=bad", "ip=192.0.2.1\nip=192.0.2.2", "ip=2001:db8::1", "ip=192.0.2.1\n" + String(repeating: "x", count: 4096)] {
            XCTAssertNil(DirectExitProbe.parse(Data(text.utf8), ipv6: false))
        }
        XCTAssertNil(DirectExitProbe.parse(Data("ip=192.0.2.1".utf8), ipv6: true))
    }

    func testUnknownMeasurementDoesNotAnnounceAllClear() {
        let snapshot = ExitSnapshot(primary: IPInfo(ip: "192.0.2.1"))
        let model = ExitIPModel(phase: .ok, lastGood: snapshot, warnings: [.tunnelExitIsDirect])
        let (updated, notes) = reduce(model, applying: .success(snapshot), context: WarningContext(onTunnel: true))
        XCTAssertTrue(updated.activeWarnings.isEmpty)
        XCTAssertTrue(notes.isEmpty)
    }

    func testDifferentFreshMeasurementClearsWarning() {
        let snapshot = ExitSnapshot(primary: IPInfo(ip: "192.0.2.1"))
        let model = ExitIPModel(phase: .ok, lastGood: snapshot, warnings: [.tunnelExitIsDirect])
        let (updated, notes) = reduce(model, applying: .success(snapshot),
                                     context: WarningContext(onTunnel: true, directExit: IPInfo(ip: "203.0.113.1")))
        XCTAssertTrue(updated.activeWarnings.isEmpty)
        XCTAssertEqual(notes.first?.title, "Exit OK")
    }

    func testCanonicalIPv6ComparisonAndDifferentFamilies() {
        XCTAssertTrue(isSameExit(IPInfo(ip: "2001:db8::1"), IPInfo(ip: "2001:0db8:0:0:0:0:0:1")))
        XCTAssertFalse(isSameExit(IPInfo(ip: "192.0.2.1"), IPInfo(ip: "2001:db8::1")))
    }
}
