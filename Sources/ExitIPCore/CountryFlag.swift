import Foundation

/// The canonical form of a 2-letter ISO country code (uppercased), or nil if
/// `code` isn't two ASCII letters.
public func normalizedCountryCode(_ code: String?) -> String? {
    guard let code = code?.trimmingCharacters(in: .whitespaces).uppercased(),
          code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else {
        return nil
    }
    return code
}

/// Maps a 2-letter ISO country code to its flag emoji, or nil if invalid.
public func flag(forCountryCode code: String) -> String? {
    guard let code = normalizedCountryCode(code) else { return nil }
    // 0x1F1E6 ("🇦") - 0x41 ("A") = 127397
    var result = ""
    for scalar in code.unicodeScalars {
        guard let flagScalar = UnicodeScalar(127397 + scalar.value) else { return nil }
        result.unicodeScalars.append(flagScalar)
    }
    return result
}

/// Flag for an `IPInfo`'s country, if it has a valid one.
func flag(for info: IPInfo) -> String? {
    info.countryCode.flatMap(flag(forCountryCode:))
}

/// English country name for a 2-letter ISO code, or nil if invalid.
public func countryName(forCountryCode code: String) -> String? {
    guard let code = normalizedCountryCode(code),
          Locale.Region.isoRegions.contains(where: { $0.identifier == code }) else {
        return nil
    }
    return Locale(identifier: "en_US").localizedString(forRegionCode: code)
}

/// ISO code for an English country name ("United States" → "US"), or nil for
/// a name that isn't recognised. Matching is case-insensitive and covers the
/// common short forms geo services use where the locale's name differs.
public func countryCode(forCountryName name: String) -> String? {
    let needle = name.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty else { return nil }
    return countryNameAliases[needle] ?? countryNameIndex[needle]
}

private let countryNameIndex: [String: String] = {
    let locale = Locale(identifier: "en_US")
    var index: [String: String] = [:]
    for region in Locale.Region.isoRegions {
        let code = region.identifier
        guard code.count == 2, let name = locale.localizedString(forRegionCode: code) else { continue }
        index[name.lowercased()] = code
    }
    return index
}()

// Apple's region names differ from what geo services send for a few places
// ("China mainland", "Türkiye", "Myanmar (Burma)").
private let countryNameAliases: [String: String] = [
    "china": "CN", "myanmar": "MM", "burma": "MM", "hong kong": "HK", "macau": "MO", "macao": "MO", "turkey": "TR", "czech republic": "CZ",
    "the netherlands": "NL", "russian federation": "RU", "south korea": "KR", "korea": "KR",
    "viet nam": "VN", "united states of america": "US", "usa": "US", "uk": "GB", "great britain": "GB",
]
