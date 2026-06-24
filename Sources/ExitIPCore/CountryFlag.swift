import Foundation

/// Maps a 2-letter ISO country code to its flag emoji, or nil if invalid.
func flag(forCountryCode code: String) -> String? {
    let upper = code.uppercased()
    let letters = Array(upper.unicodeScalars)
    guard letters.count == 2, letters.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else {
        return nil
    }
    // 0x1F1E6 ("🇦") - 0x41 ("A") = 127397
    var result = ""
    for scalar in letters {
        guard let flagScalar = UnicodeScalar(127397 + scalar.value) else { return nil }
        result.unicodeScalars.append(flagScalar)
    }
    return result
}

/// English country name for a 2-letter ISO code, or nil if invalid.
func countryName(forCountryCode code: String) -> String? {
    let normalized = code.trimmingCharacters(in: .whitespaces).uppercased()
    guard normalized.count == 2, normalized.allSatisfy({ $0.isASCII && $0.isLetter }) else {
        return nil
    }
    guard Locale.Region.isoRegions.contains(where: { $0.identifier == normalized }) else {
        return nil
    }
    return Locale(identifier: "en_US").localizedString(forRegionCode: normalized)
}
