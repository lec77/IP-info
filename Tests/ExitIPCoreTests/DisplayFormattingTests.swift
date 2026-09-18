import XCTest
@testable import ExitIPCore

final class DisplayFormattingTests: XCTestCase {
    private let full = IPInfo(ip: "1.2.3.4", city: "San Jose", region: "California",
                             countryCode: "US", countryName: "United States", isp: "Cloudflare, Inc.")
    private func ok(_ info: IPInfo, warnings: [ExitWarning] = []) -> ExitIPModel {
        ExitIPModel(phase: .ok, lastGood: ExitSnapshot(primary: info), warnings: warnings)
    }

    func testTitleInitial() {
        XCTAssertEqual(menuBarTitle(for: ExitIPModel()), "…")
    }

    func testTitleOkFlagAndCity() {
        XCTAssertEqual(menuBarTitle(for: ok(full)), "🇺🇸 San Jose")
    }

    func testTitleOkFlagNoCity() {
        XCTAssertEqual(menuBarTitle(for: ok(IPInfo(ip: "1.2.3.4", countryCode: "US"))), "🇺🇸")
    }

    func testTitleOkCityNoFlag() {
        // No country flag means geo lookup was incomplete -> mark it.
        XCTAssertEqual(menuBarTitle(for: ok(IPInfo(ip: "1.2.3.4", city: "San Jose"))), "⚠︎ San Jose")
    }

    func testTitleOkIPOnlyShowsWarning() {
        // Only the address providers responded — geo degraded. Must be visibly
        // marked, not a bare IP that looks like a normal reading.
        XCTAssertEqual(menuBarTitle(for: ok(IPInfo(ip: "1.2.3.4"))), "⚠︎ 1.2.3.4")
    }

    func testTitleOffline() {
        XCTAssertEqual(menuBarTitle(for: ExitIPModel(phase: .failed(.offline), lastGood: ExitSnapshot(primary: full))), "⚠︎ offline")
    }

    func testTitleCaptivePortal() {
        XCTAssertEqual(menuBarTitle(for: ExitIPModel(phase: .failed(.captivePortal), lastGood: ExitSnapshot(primary: full))), "⚠︎ captive portal")
    }

    func testTitleTunnelDown() {
        XCTAssertEqual(menuBarTitle(for: ExitIPModel(phase: .failed(.tunnelDown), lastGood: ExitSnapshot(primary: full))), "⚠︎ tunnel down")
    }

    func testTitleLookupFailedWithLastKnown() {
        XCTAssertEqual(menuBarTitle(for: ExitIPModel(phase: .failed(.lookupFailed), lastGood: ExitSnapshot(primary: full))), "⚠︎ 🇺🇸 San Jose")
    }

    func testTitleLookupFailedNoLastKnown() {
        XCTAssertEqual(menuBarTitle(for: ExitIPModel(phase: .failed(.lookupFailed), lastGood: nil)), "⚠︎")
    }

    func testTitlePaused() {
        XCTAssertEqual(menuBarTitle(for: ok(full), paused: true), "⏸ 🇺🇸 San Jose")
        XCTAssertEqual(menuBarTitle(for: ExitIPModel(), paused: true), "⏸ …")
        XCTAssertEqual(menuBarTitle(for: ExitIPModel(phase: .failed(.offline)), paused: true), "⏸ ⚠︎ offline")
    }

    func testTitleUsesLoudestWarning() {
        XCTAssertEqual(menuBarTitle(for: ok(full, warnings: [.unexpectedCountry])), "⛔ 🇺🇸 San Jose")
        XCTAssertEqual(menuBarTitle(for: ok(full, warnings: [.tunnelExitIsHome, .unexpectedCountry]), paused: true), "⏸ ⛔ 🇺🇸 San Jose")
        XCTAssertEqual(menuBarTitle(for: ok(full, warnings: [.ipv6Mismatch])), "⚠︎ 🇺🇸 San Jose")
        XCTAssertEqual(menuBarTitle(for: ok(full, warnings: [.tunnelExitIsHome])), "⚠︎ 🇺🇸 San Jose")
    }

    func testWarningsIgnoredWhenNotOk() {
        // Stale warnings must not decorate a failure title.
        let model = ExitIPModel(phase: .failed(.offline), lastGood: ExitSnapshot(primary: full), warnings: [.unexpectedCountry])
        XCTAssertEqual(model.activeWarnings, [])
        XCTAssertEqual(menuBarTitle(for: model), "⚠︎ offline")
    }

    func testNoDoubleWarningPrefix() {
        let noFlag = IPInfo(ip: "1.2.3.4", city: "San Jose")
        XCTAssertEqual(menuBarTitle(for: ok(noFlag, warnings: [.tunnelExitIsHome])), "⚠︎ San Jose")
    }

    func testSeverityOrderAndGlyphs() {
        XCTAssertLessThan(ExitWarning.Severity.caution, .critical)
        XCTAssertEqual(ExitWarning.Severity.critical.glyph, "⛔")
        XCTAssertEqual(ExitWarning.Severity.caution.glyph, "⚠︎")
        XCTAssertEqual(ExitWarning.unexpectedCountry.severity, .critical)
        XCTAssertEqual(ExitWarning.ipv6Mismatch.severity, .caution)
        XCTAssertEqual(ExitWarning.tunnelExitIsHome.severity, .caution)
    }

    func testLines() {
        XCTAssertEqual(ipLine(for: full), "IP: 1.2.3.4")
        XCTAssertEqual(ipv6Line(for: IPInfo(ip: "2001:db8::1")), "IPv6: 2001:db8::1")
        XCTAssertEqual(locationLine(for: full), "Location: San Jose, United States")
        XCTAssertEqual(ispLine(for: full), "ISP: Cloudflare, Inc.")
    }

    func testLinesOmittedWhenMissing() {
        let info = IPInfo(ip: "1.2.3.4")
        XCTAssertNil(locationLine(for: info))
        XCTAssertNil(ispLine(for: info))
    }

    func testDurationText() {
        XCTAssertEqual(durationText(seconds: 0), "0s")
        XCTAssertEqual(durationText(seconds: 45), "45s")
        XCTAssertEqual(durationText(seconds: 12 * 60 + 5), "12m")
        XCTAssertEqual(durationText(seconds: 2 * 3600), "2h")
        XCTAssertEqual(durationText(seconds: 3 * 3600 + 12 * 60), "3h 12m")
        XCTAssertEqual(durationText(seconds: 3 * 86400), "3d")
        XCTAssertEqual(durationText(seconds: 2 * 86400 + 5 * 3600 + 7), "2d 5h")
        XCTAssertEqual(durationText(seconds: -9), "0s")
        XCTAssertEqual(stableForText(seconds: 3 * 3600 + 12 * 60), "Unchanged for 3h 12m")
    }

    func testCheckingText() {
        XCTAssertEqual(checkingText, "Last checked: checking…")
    }

    func testLastCheckedText() {
        XCTAssertEqual(lastCheckedText(secondsAgo: 3), "Last checked: just now")
        XCTAssertEqual(lastCheckedText(secondsAgo: 12), "Last checked: 12s ago")
        XCTAssertEqual(lastCheckedText(secondsAgo: 90), "Last checked: 1m ago")
        XCTAssertEqual(lastCheckedText(secondsAgo: 7200), "Last checked: 2h ago")
        XCTAssertEqual(lastCheckedText(secondsAgo: 3 * 3600 + 12 * 60), "Last checked: 3h 12m ago")
    }

    func testLatencyLine() {
        XCTAssertEqual(latencyLine(ms: 85), "Latency: 85 ms")
        XCTAssertEqual(latencyLine(ms: nil), "Latency: —")
        XCTAssertEqual(latencyLine(ms: 85, trend: [85]), "Latency: 85 ms", "one sample is no trend")
        XCTAssertEqual(latencyLine(ms: 85, trend: [40, 85]), "Latency: 85 ms ▄█")
        XCTAssertEqual(latencyLine(ms: nil, trend: [40, nil]), "Latency: — █·")
    }

    func testLatencyTrend() {
        XCTAssertNil(latencyTrend([]))
        XCTAssertNil(latencyTrend([50]))
        XCTAssertEqual(latencyTrend([100, 100]), "██", "scaled to the peak")
        XCTAssertEqual(latencyTrend([0, 50, 100]), "▁▅█")
        XCTAssertEqual(latencyTrend([10, 20, 30, 40, 50, 60, 70, 80]), "▂▃▄▅▅▆▇█", "levels are rounded, not floored")
        XCTAssertEqual(latencyTrend([nil, nil]), "··", "no latency at all still draws")
        XCTAssertEqual(latencyTrend([80, nil, 20]), "█·▃")
        XCTAssertEqual(latencyTrend([-5, 10]), "▁█", "negative clamps to the floor")
    }

    func testDNSLine() {
        XCTAssertEqual(dnsLine(for: IPInfo(ip: "172.253.9.222", countryCode: "US", isp: "Google LLC")), "DNS: 🇺🇸 Google LLC")
        XCTAssertEqual(dnsLine(for: IPInfo(ip: "172.253.9.222", countryCode: "US")), "DNS: 🇺🇸")
        XCTAssertEqual(dnsLine(for: IPInfo(ip: "172.253.9.222")), "DNS: 172.253.9.222")
    }

    func testCountryLabel() {
        XCTAssertEqual(countryLabel("US"), "🇺🇸 United States")
        XCTAssertEqual(countryLabel("de"), "🇩🇪 Germany")
        XCTAssertEqual(countryLabel("ZZ"), "🇿🇿 ZZ") // flag pattern is valid, name unknown
        XCTAssertEqual(countryLabel("USA"), "USA")  // not a code: shown as-is
        XCTAssertEqual(countryLabel(nil), "?")
    }

    func testExitSummary() {
        XCTAssertEqual(exitSummary(full), "🇺🇸 San Jose · 1.2.3.4")
        XCTAssertEqual(exitSummary(IPInfo(ip: "1.2.3.4")), "1.2.3.4")
    }

    func testPollIntervalLabel() {
        XCTAssertEqual(pollIntervalLabel(15), "15 seconds")
        XCTAssertEqual(pollIntervalLabel(1), "1 second")
        XCTAssertEqual(pollIntervalLabel(60), "1 minute")
        XCTAssertEqual(pollIntervalLabel(120), "2 minutes")
        XCTAssertEqual(pollIntervalLabel(600), "10 minutes")
        XCTAssertEqual(pollIntervalLabel(90), "1 min 30 s")
    }

    func testValidPollInterval() {
        XCTAssertTrue(Config.pollIntervalChoices.contains(Config.pollInterval))
        XCTAssertEqual(Config.pollIntervalChoices, Config.pollIntervalChoices.sorted())
        XCTAssertEqual(validPollInterval(nil), Config.pollInterval)
        XCTAssertEqual(validPollInterval(300), 300)
        XCTAssertEqual(validPollInterval(7), Config.pollInterval, "not an offered choice")
        XCTAssertEqual(validPollInterval(0), Config.pollInterval)
    }
}
