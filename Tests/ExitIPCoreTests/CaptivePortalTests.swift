import XCTest
@testable import ExitIPCore

final class CaptivePortalTests: XCTestCase {
    private let probeURL = URL(string: "http://www.gstatic.com/generate_204")!

    // MARK: Response head parsing

    func testParsesStatusAndHeaders() {
        let raw = Data("HTTP/1.1 302 Found\r\nLocation: http://10.0.0.1/login\r\nContent-Length: 0\r\n\r\nbody".utf8)
        XCTAssertTrue(httpHeadIsComplete(raw))
        let head = parseHTTPResponseHead(raw)
        XCTAssertEqual(head?.statusCode, 302)
        XCTAssertEqual(head?.header("location"), "http://10.0.0.1/login")
        XCTAssertEqual(head?.header("LOCATION"), "http://10.0.0.1/login", "header lookup is case-insensitive")
        XCTAssertEqual(head?.header("content-length"), "0")
    }

    func testHeaderNamesAreCaseInsensitiveAndFirstWins() {
        let raw = Data("HTTP/1.0 302 Moved\r\nlocation: /first\r\nLocation: /second\r\n\r\n".utf8)
        XCTAssertEqual(parseHTTPResponseHead(raw)?.header("Location"), "/first")
    }

    func testBareLineFeedsAccepted() {
        let raw = Data("HTTP/1.1 200 OK\nContent-Type: text/html\n\n<html>".utf8)
        XCTAssertTrue(httpHeadIsComplete(raw))
        XCTAssertEqual(parseHTTPResponseHead(raw), HTTPResponseHead(statusCode: 200, headers: ["content-type": "text/html"]))
    }

    func testIncompleteHeadIsNil() {
        let raw = Data("HTTP/1.1 302 Found\r\nLocation: http://portal/\r\n".utf8)
        XCTAssertFalse(httpHeadIsComplete(raw))
        XCTAssertNil(parseHTTPResponseHead(raw))
    }

    func testNonHTTPIsNil() {
        XCTAssertNil(parseHTTPResponseHead(Data("<html>not http</html>\r\n\r\n".utf8)))
        XCTAssertNil(parseHTTPResponseHead(Data("HTTP/1.1 abc\r\n\r\n".utf8)))
        XCTAssertNil(parseHTTPResponseHead(Data("HTTP/1.1 999 Nope\r\n\r\n".utf8)))
        XCTAssertNil(parseHTTPResponseHead(Data()))
    }

    func testStatusWithoutReasonOrHeaders() {
        XCTAssertEqual(parseHTTPResponseHead(Data("HTTP/1.1 204\r\n\r\n".utf8)), HTTPResponseHead(statusCode: 204))
    }

    func testNonUTF8BytesDoNotBreakParsing() {
        var raw = Data("HTTP/1.1 302 Found\r\nLocation: http://portal.example/\r\nX-Junk: ".utf8)
        raw.append(contentsOf: [0xFF, 0xFE, 0xC0])
        raw.append(contentsOf: Data("\r\n\r\n".utf8))
        XCTAssertEqual(parseHTTPResponseHead(raw)?.header("location"), "http://portal.example/")
    }

    // MARK: Redirect target

    func testAbsoluteRedirect() {
        let head = HTTPResponseHead(statusCode: 302, headers: ["location": "https://portal.example.com/login?next=x"])
        XCTAssertEqual(portalRedirectURL(from: head, requestURL: probeURL)?.absoluteString, "https://portal.example.com/login?next=x")
    }

    func testRelativeRedirectResolvesAgainstProbeURL() {
        let head = HTTPResponseHead(statusCode: 307, headers: ["location": "/login?x=1"])
        XCTAssertEqual(portalRedirectURL(from: head, requestURL: probeURL)?.absoluteString, "http://www.gstatic.com/login?x=1")
    }

    func testRedirectRequiresThreeHundredWithHTTPLocation() {
        XCTAssertNil(portalRedirectURL(from: HTTPResponseHead(statusCode: 302), requestURL: probeURL), "no Location")
        XCTAssertNil(portalRedirectURL(from: HTTPResponseHead(statusCode: 302, headers: ["location": "   "]), requestURL: probeURL))
        XCTAssertNil(portalRedirectURL(from: HTTPResponseHead(statusCode: 200, headers: ["location": "http://p/"]), requestURL: probeURL), "2xx: portal served its own page, nothing to open")
        XCTAssertNil(portalRedirectURL(from: HTTPResponseHead(statusCode: 302, headers: ["location": "javascript:alert(1)"]), requestURL: probeURL))
        XCTAssertNil(portalRedirectURL(from: HTTPResponseHead(statusCode: 302, headers: ["location": "file:///etc/passwd"]), requestURL: probeURL))
    }

    // MARK: Local hosts

    func testLocalHosts() {
        for host in ["10.93.115.1", "192.168.1.1", "172.16.0.1", "172.31.255.254", "169.254.1.1", "127.0.0.1", "localhost",
                     "::1", "fe80::1", "fd00::1", "[fe80::1]", "gateway.local", "router.lan", "portal", "wifi.home.arpa"] {
            XCTAssertTrue(isLocalHost(host), host)
        }
    }

    func testPublicHosts() {
        for host in ["captive.apple.com", "8.8.8.8", "172.32.0.1", "172.15.0.1", "11.0.0.1", "2001:db8::1", "portal.example.com", "1.1.1.1", ""] {
            XCTAssertFalse(isLocalHost(host), host)
        }
    }

    // MARK: Sign-in target

    func testSignInUsesRedirectWhenCaught() {
        let redirect = URL(string: "http://10.93.115.1/login")!
        XCTAssertEqual(portalSignIn(redirect: redirect), PortalSignIn(url: redirect, isLocal: true))
        let publicRedirect = URL(string: "https://portal.example.com/")!
        XCTAssertEqual(portalSignIn(redirect: publicRedirect), PortalSignIn(url: publicRedirect, isLocal: false))
    }

    func testSignInFallsBackToPlainHTTPPage() {
        XCTAssertEqual(portalSignIn(redirect: nil), PortalSignIn(url: Config.captivePortalSignInURL, isLocal: false))
        XCTAssertEqual(Config.captivePortalSignInURL.scheme, "http", "a portal can only intercept plain HTTP")
    }

    // MARK: Menu text

    func testPortalStatusFollowsModelPhase() {
        let signIn = PortalSignIn(url: URL(string: "http://10.93.115.1/login")!, isLocal: true)
        XCTAssertEqual(portalStatus(for: ExitIPModel(phase: .failed(.captivePortal)), signIn: signIn), .signInRequired(host: "10.93.115.1"))
        XCTAssertEqual(portalStatus(for: ExitIPModel(phase: .failed(.captivePortal)), signIn: nil), .signInRequired(host: nil))
        XCTAssertEqual(portalStatus(for: ExitIPModel(phase: .ok), signIn: nil), .notDetected)
        XCTAssertEqual(portalStatus(for: ExitIPModel(phase: .failed(.lookupFailed)), signIn: nil), .notDetected, "probe got through; only the lookup failed")
        XCTAssertEqual(portalStatus(for: ExitIPModel(phase: .failed(.tunnelDown)), signIn: nil), .notDetected, "the direct probe got through")
        XCTAssertEqual(portalStatus(for: ExitIPModel(phase: .failed(.offline)), signIn: nil), .unknown)
        XCTAssertEqual(portalStatus(for: ExitIPModel(phase: .initial), signIn: nil), .unknown)
    }

    func testMenuTitleNamesPortalHostOnly() {
        XCTAssertEqual(signInMenuTitle(.signInRequired(host: "10.93.115.1")), "Open sign-in page (10.93.115.1)…")
        XCTAssertEqual(signInMenuTitle(.signInRequired(host: nil)), "Open sign-in page…")
        XCTAssertEqual(signInMenuTitle(.signInRequired(host: "")), "Open sign-in page…")
        XCTAssertEqual(signInMenuTitle(.notDetected), "Open sign-in page…")
        XCTAssertEqual(signInMenuTitle(.unknown), "Open sign-in page…")
    }

    func testBadgeSaysWhetherSignInIsNeeded() {
        XCTAssertEqual(signInBadge(.signInRequired(host: "10.93.115.1")), SignInBadge(text: "Sign-in required", tone: .alert))
        XCTAssertEqual(signInBadge(.signInRequired(host: nil)), SignInBadge(text: "Sign-in required", tone: .alert))
        XCTAssertEqual(signInBadge(.notDetected), SignInBadge(text: "No portal", tone: .ok))
        XCTAssertEqual(signInBadge(.unknown), SignInBadge(text: "Unknown", tone: .neutral))
    }

    func testTunnelHintOnlyForNonLocalPagesOnATunnel() {
        let lan = PortalSignIn(url: URL(string: "http://10.0.0.1/")!, isLocal: true)
        let wan = PortalSignIn(url: URL(string: "http://captive.apple.com/hotspot-detect.html")!, isLocal: false)
        XCTAssertNil(signInHint(wan, viaTunnel: false))
        XCTAssertNil(signInHint(lan, viaTunnel: true), "LAN addresses stay reachable alongside a tunnel")
        XCTAssertEqual(signInHint(wan, viaTunnel: true), "⚠︎ Turn off the VPN/proxy tunnel first, or the page won't load")
    }

    // MARK: Interfaces

    func testPhysicalInterfaceKinds() {
        XCTAssertTrue(InterfaceKind.wifi.isPhysical)
        XCTAssertTrue(InterfaceKind.wired.isPhysical)
        XCTAssertTrue(InterfaceKind.cellular.isPhysical)
        XCTAssertFalse(InterfaceKind.tunnel.isPhysical)
        XCTAssertFalse(InterfaceKind.loopback.isPhysical)
        XCTAssertFalse(InterfaceKind.other.isPhysical)
    }
}
