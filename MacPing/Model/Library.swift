import Foundation

/// A saved set of hosts, loaded in one go
struct Favorite: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var hosts: [String]
    /// 0 is automatic
    var columns: Int

    var id: String { name }
}

/// A host going up or down, or a monitor starting or stopping
struct StatusEvent: Identifiable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case up, down, start, stop

        var label: String { rawValue.capitalized }
    }

    let id: Int
    let date: Date
    let host: String
    let alias: String?
    let kind: Kind

    var name: String { alias ?? host }
}

/// What's kept between launches, apart from settings: aliases, favourites
/// and the last hosts. One JSON file in Application Support.
struct Library: Codable, Equatable, Sendable {
    /// Host → the name to show for it
    var aliases: [String: String] = [:]
    var favorites: [Favorite] = []
    var lastHosts: [String] = []
    var lastColumns = 0

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPing/Library.json")
    }

    static func load(from url: URL?) -> Library {
        guard let url, let data = try? Data(contentsOf: url),
              let library = try? JSONDecoder().decode(Library.self, from: data) else { return Library() }
        return library
    }

    func save(to url: URL?) {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Aliases are matched without caring about case or a port
    static func aliasKey(_ host: String) -> String { host.lowercased() }
}

/// Status history as text, for Export
enum HistoryExport {
    enum Delimiter: String, CaseIterable, Sendable {
        case comma, tab, space

        var character: String {
            switch self {
            case .comma: return ","
            case .tab: return "\t"
            case .space: return " "
            }
        }

        var fileExtension: String { self == .comma ? "csv" : "txt" }
        var label: String { self == .comma ? "CSV" : rawValue.capitalized }
    }

    static func text(_ events: [StatusEvent], delimiter: Delimiter) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        let sep = delimiter.character
        func field(_ value: String) -> String {
            switch delimiter {
            case .comma:
                return value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline })
                    ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
            case .tab, .space:
                return value.replacingOccurrences(of: sep, with: "_")
            }
        }
        var lines = [["Time", "Host", "Alias", "Status"].joined(separator: sep)]
        for event in events {
            lines.append([formatter.string(from: event.date), event.host, event.alias ?? "", event.kind.label]
                .map(field).joined(separator: sep))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
