/// Compact menu-bar label: country flag + city (e.g. "🇺🇸 San Jose"), kept short
/// so it doesn't get clipped behind the menu-bar notch. Degrades to flag-only,
/// city-only, then the IP when those fields are missing. (Full IP lives in the
/// dropdown via `ipLine`.)
func placeLabel(for info: IPInfo) -> String {
    let flagStr = info.countryCode.flatMap(flag(forCountryCode:))
    let city = info.city.flatMap { $0.isEmpty ? nil : $0 }
    switch (flagStr, city) {
    case let (f?, c?): return "\(f) \(c)"
    case let (f?, nil): return f
    case let (nil, c?): return c
    case (nil, nil): return info.ip
    }
}

public func menuBarTitle(for model: ExitIPModel) -> String {
    switch model.phase {
    case .initial:
        return "…"
    case .ok:
        guard let info = model.lastGoodIP else { return "…" }
        return placeLabel(for: info)
    case .failed(.offline):
        return "⚠︎ offline"
    case .failed(.lookupFailed):
        if let info = model.lastGoodIP { return "⚠︎ \(placeLabel(for: info))" }
        return "⚠︎"
    }
}

public func ipLine(for info: IPInfo) -> String {
    "IP: \(info.ip)"
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

public func lastCheckedText(secondsAgo: Int) -> String {
    let s = max(0, secondsAgo)
    if s < 5 { return "Last checked: just now" }
    if s < 60 { return "Last checked: \(s)s ago" }
    if s < 3600 { return "Last checked: \(s / 60)m ago" }
    return "Last checked: \(s / 3600)h ago"
}
