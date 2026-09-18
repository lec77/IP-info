import Foundation

/// The status line and headers of an HTTP/1.x response, parsed from raw bytes.
/// Header names are stored lowercased; the first occurrence of a repeated
/// header wins.
public struct HTTPResponseHead: Sendable, Equatable {
    public var statusCode: Int
    public var headers: [String: String]

    public init(statusCode: Int, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.headers = headers
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

private let crlfTerminator = Data("\r\n\r\n".utf8)
private let lfTerminator = Data("\n\n".utf8)

/// Whether the buffer holds a complete head, i.e. the blank line after the
/// headers has arrived. Bare-LF line endings are accepted: captive portals are
/// not known for their standards compliance.
public func httpHeadIsComplete(_ data: Data) -> Bool {
    headTerminatorRange(in: data) != nil
}

/// Parses a response head. Returns nil while the head is incomplete, or when
/// the status line is not a valid HTTP/1.x one.
public func parseHTTPResponseHead(_ data: Data) -> HTTPResponseHead? {
    guard let terminator = headTerminatorRange(in: data) else { return nil }
    // Latin-1 decodes any byte sequence, so a portal's odd bytes can't derail parsing.
    guard let text = String(data: data[data.startIndex..<terminator.lowerBound], encoding: .isoLatin1) else { return nil }
    // Swift treats "\r\n" as one Character, so normalise before splitting on "\n".
    var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    guard let statusLine = lines.first else { return nil }
    lines.removeFirst()

    let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
    guard parts.count >= 2, parts[0].uppercased().hasPrefix("HTTP/"),
          let status = Int(parts[1]), (100...599).contains(status) else { return nil }

    var headers: [String: String] = [:]
    for line in lines {
        guard let colon = line.firstIndex(of: ":") else { continue }
        let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, headers[name] == nil else { continue }
        headers[name] = value
    }
    return HTTPResponseHead(statusCode: status, headers: headers)
}

private func headTerminatorRange(in data: Data) -> Range<Data.Index>? {
    let crlf = data.range(of: crlfTerminator)
    let lf = data.range(of: lfTerminator)
    switch (crlf, lf) {
    case let (a?, b?): return a.lowerBound < b.lowerBound ? a : b
    case let (a?, nil): return a
    case let (nil, b?): return b
    case (nil, nil): return nil
    }
}
