import Foundation

/// What a monitor watches: a host to ping, or a host and TCP port to connect to.
/// Typed as `example.com`, `10.0.0.1`, `fe80::1`, `example.com:443` or `[fe80::1]:22`.
struct Target: Hashable, Codable, Sendable {
    let host: String
    /// Set for a TCP "port ping"
    let port: UInt16?

    var isPortCheck: Bool { port != nil }

    /// As the user would type it
    var text: String {
        guard let port else { return host }
        return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    init(host: String, port: UInt16? = nil) {
        self.host = host
        self.port = port
    }

    /// Nil for empty or malformed text
    init?(parsing raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        // [IPv6]:port or [IPv6]
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { return nil }
            let host = String(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...]
            guard !host.isEmpty else { return nil }
            if rest.isEmpty { self.init(host: host); return }
            guard rest.hasPrefix(":"), let port = Self.port(rest.dropFirst()) else { return nil }
            self.init(host: host, port: port)
            return
        }
        let colons = text.filter { $0 == ":" }.count
        // More than one colon: a bare IPv6 address, which has no port
        if colons > 1 { self.init(host: text); return }
        if colons == 1 {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard !parts[0].isEmpty, let port = Self.port(parts[1]) else { return nil }
            self.init(host: String(parts[0]), port: port)
            return
        }
        self.init(host: text)
    }

    private static func port(_ text: Substring) -> UInt16? {
        guard let value = UInt16(text), value > 0 else { return nil }
        return value
    }

    /// Hosts from pasted or dropped text: one per line, or separated by commas,
    /// semicolons or spaces. Blank and unreadable entries are skipped, and so
    /// are `#` comments.
    static func list(from text: String) -> [Target] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "" }
            .flatMap { $0.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " || $0 == "\t" }) }
            .compactMap { Target(parsing: String($0)) }
    }
}
