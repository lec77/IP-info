/// Compact menu-bar label: country flag + city (e.g. "🇺🇸 San Jose"), kept short
/// so it doesn't get clipped behind the menu-bar notch. Degrades to flag-only,
/// city-only, then the IP when those fields are missing. (Full IP lives in the
/// dropdown via `ipLine`.)
func placeLabel(for info: IPInfo) -> String {
    let city = info.city.flatMap { $0.isEmpty ? nil : $0 }
    switch (flag(for: info), city) {
    case let (f?, c?): return "\(f) \(c)"
    case let (f?, nil): return f
    case let (nil, c?): return c
    case (nil, nil): return info.ip
    }
}

/// Menu-bar title. Prefix legend: "⛔" the exit is not where you expect it,
/// "⚠︎" degraded (offline, portal, partial geo) or a leak warning, "⏸" paused.
public func menuBarTitle(for model: ExitIPModel, paused: Bool = false) -> String {
    let base = baseTitle(for: model)
    return paused ? "⏸ \(base)" : base
}

private func baseTitle(for model: ExitIPModel) -> String {
    switch model.phase {
    case .initial:
        return "…"
    case .ok:
        guard let info = model.lastGoodIP else { return "…" }
        let label = placeLabel(for: info)
        // The loudest active warning wins. A normal reading always has a country
        // flag; no flag means geo only partially succeeded — surface that as a
        // caution too, instead of a bare IP that looks like a normal reading.
        let severity = model.activeWarnings.map(\.severity).max()
            ?? (flag(for: info) == nil ? .caution : nil)
        return severity.map { "\($0.glyph) \(label)" } ?? label
    case .failed(.offline):
        return "⚠︎ offline"
    case .failed(.captivePortal):
        return "⚠︎ captive portal"
    case .failed(.lookupFailed):
        if let info = model.lastGoodIP { return "⚠︎ \(placeLabel(for: info))" }
        return "⚠︎"
    }
}

public func ipLine(for info: IPInfo) -> String {
    "IP: \(info.ip)"
}

public func ipv6Line(for info: IPInfo) -> String {
    "IPv6: \(info.ip)"
}

public func locationLine(for info: IPInfo) -> String? {
    let parts = [info.city, info.countryName].compactMap { $0 }.filter { !$0.isEmpty }
    guard !parts.isEmpty else { return nil }
    return "Location: " + parts.joined(separator: ", ")
}

public func ispLine(for info: IPInfo) -> String? {
    guard let isp = info.isp, !isp.isEmpty else { return nil }
    return "ISP: \(isp)"
}

/// "45s", "12m", "3h 12m", "2h", "2d 5h".
public func durationText(seconds: Int) -> String {
    let s = max(0, seconds)
    if s < 60 { return "\(s)s" }
    let m = s / 60
    if m < 60 { return "\(m)m" }
    let h = m / 60
    if h < 24 { return m % 60 == 0 ? "\(h)h" : "\(h)h \(m % 60)m" }
    return h % 24 == 0 ? "\(h / 24)d" : "\(h / 24)d \(h % 24)h"
}

public func stableForText(seconds: Int) -> String {
    "Unchanged for \(durationText(seconds: seconds))"
}

public func lastCheckedText(secondsAgo: Int) -> String {
    let s = max(0, secondsAgo)
    return s < 5 ? "Last checked: just now" : "Last checked: \(durationText(seconds: s)) ago"
}

public func latencyLine(ms: Int?) -> String {
    guard let ms else { return "Latency: —" }
    return "Latency: \(ms) ms"
}

/// "🇺🇸 United States", falling back to the bare code, or "?" for none.
public func countryLabel(_ code: String?) -> String {
    guard let code = normalizedCountryCode(code) else { return code ?? "?" }
    let name = countryName(forCountryCode: code) ?? code
    return "\(flag(forCountryCode: code) ?? "") \(name)".trimmingCharacters(in: .whitespaces)
}

/// Short exit description for notifications: "🇺🇸 San Jose · 1.2.3.4".
public func exitSummary(_ info: IPInfo) -> String {
    let place = placeLabel(for: info)
    return place == info.ip ? info.ip : "\(place) · \(info.ip)"
}

/// Compact form for change notifications: "1.2.3.4 (US)".
func ipWithCountryCode(_ info: IPInfo) -> String {
    if let cc = info.countryCode, !cc.isEmpty {
        return "\(info.ip) (\(cc))"
    }
    return info.ip
}
