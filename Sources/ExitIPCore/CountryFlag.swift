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
