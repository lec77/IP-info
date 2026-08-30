import Foundation

/// A change of the primary exit address. `from` is nil for the first observation.
public struct IPChangeEvent: Sendable, Equatable, Codable {
    public var date: Date
    public var from: IPInfo?
    public var to: IPInfo

    public init(date: Date, from: IPInfo?, to: IPInfo) {
        self.date = date
        self.from = from
        self.to = to
    }
}

/// Appends an event when `info` differs (by address) from the last recorded
/// exit, or when the history is empty. Returns the history unchanged otherwise.
/// Keeps the newest `limit` entries.
public func recordingExit(
    _ info: IPInfo,
    in history: [IPChangeEvent],
    at date: Date,
    limit: Int = Config.historyLimit
) -> [IPChangeEvent] {
    if let last = history.last, last.to.ip == info.ip { return history }
    var updated = history
    updated.append(IPChangeEvent(date: date, from: history.last?.to, to: info))
    if updated.count > limit { updated.removeFirst(updated.count - limit) }
    return updated
}

/// Time of an event for the history menu: clock time if today, else date + time.
public func historyTimeText(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
    if calendar.isDate(date, inSameDayAs: now) {
        return date.formatted(date: .omitted, time: .shortened)
    }
    return date.formatted(date: .abbreviated, time: .shortened)
}

/// "14:02  🇺🇸 → 🇩🇪  5.6.7.8", or "14:02  🇺🇸 1.2.3.4 (first seen)".
public func historyLine(_ event: IPChangeEvent, timeText: String) -> String {
    let to = flag(for: event.to) ?? "?"
    guard let from = event.from else {
        return "\(timeText)  \(to) \(event.to.ip) (first seen)"
    }
    return "\(timeText)  \(flag(for: from) ?? "?") → \(to)  \(event.to.ip)"
}
