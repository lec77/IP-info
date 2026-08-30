import XCTest
@testable import ExitIPCore

final class HistoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let us = IPInfo(ip: "1.1.1.1", countryCode: "US")
    private let de = IPInfo(ip: "2.2.2.2", countryCode: "DE")

    func testFirstObservationIsRecordedWithoutFrom() {
        let h = recordingExit(us, in: [], at: t0)
        XCTAssertEqual(h, [IPChangeEvent(date: t0, from: nil, to: us)])
    }

    func testUnchangedAddressIsNotRecorded() {
        let h = recordingExit(us, in: [], at: t0)
        let again = recordingExit(IPInfo(ip: "1.1.1.1", city: "moved"), in: h, at: t0 + 60)
        XCTAssertEqual(again, h) // same address, geo details don't matter
    }

    func testChangeIsRecordedWithPrevious() {
        var h = recordingExit(us, in: [], at: t0)
        h = recordingExit(de, in: h, at: t0 + 60)
        XCTAssertEqual(h.count, 2)
        XCTAssertEqual(h.last, IPChangeEvent(date: t0 + 60, from: us, to: de))
    }

    func testLimitDropsOldest() {
        var h: [IPChangeEvent] = []
        for i in 0..<10 {
            h = recordingExit(IPInfo(ip: "10.0.0.\(i)"), in: h, at: t0 + Double(i), limit: 3)
        }
        XCTAssertEqual(h.map(\.to.ip), ["10.0.0.7", "10.0.0.8", "10.0.0.9"])
    }


    func testHistoryLines() {
        XCTAssertEqual(historyLine(IPChangeEvent(date: t0, from: nil, to: us), timeText: "14:02"),
                       "14:02  🇺🇸 1.1.1.1 (first seen)")
        XCTAssertEqual(historyLine(IPChangeEvent(date: t0, from: us, to: de), timeText: "14:05"),
                       "14:05  🇺🇸 → 🇩🇪  2.2.2.2")
        XCTAssertEqual(historyLine(IPChangeEvent(date: t0, from: IPInfo(ip: "9.9.9.9"), to: de), timeText: "t"),
                       "t  ? → 🇩🇪  2.2.2.2")
    }

    func testHistoryTimeTextShorterForToday() {
        let cal = Calendar(identifier: .gregorian)
        let sameDay = historyTimeText(t0, now: t0 + 3600, calendar: cal)
        let otherDay = historyTimeText(t0, now: t0 + 3 * 86400, calendar: cal)
        XCTAssertFalse(sameDay.isEmpty)
        XCTAssertGreaterThan(otherDay.count, sameDay.count)
    }

    func testEventRoundTripsThroughJSON() throws {
        let events = [IPChangeEvent(date: t0, from: nil, to: us), IPChangeEvent(date: t0 + 1, from: us, to: de)]
        let decoded = try JSONDecoder().decode([IPChangeEvent].self, from: JSONEncoder().encode(events))
        XCTAssertEqual(decoded, events)
    }
}
