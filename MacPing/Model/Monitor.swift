import AppKit
import Foundation
import Observation
@preconcurrency import UserNotifications

/// Everything the window and the menu bar show: the monitors, their history,
/// aliases and favourites. One per app.
@MainActor
@Observable
final class Monitor {
    let settings: AppSettings
    let updater = SelfUpdater(app: .macPing)
    private(set) var probes: [Probe] = []
    /// Columns in the grid; 0 fits them to the window
    var columns = 0 { didSet { saveSession() } }
    /// The favourite loaded, for the window title
    private(set) var favoriteName: String?
    private(set) var library: Library
    private(set) var history: [StatusEvent] = []
    static let maxHistory = 5000

    @ObservationIgnored let options: OptionsBox
    @ObservationIgnored private let libraryURL: URL?
    @ObservationIgnored private let alerts: Alerts
    @ObservationIgnored private var nextEvent = 0
    /// Demo data and tests: no notifications, sounds or files
    @ObservationIgnored var quiet = false

    init(settings: AppSettings = AppSettings(), libraryURL: URL? = Library.defaultURL) {
        self.settings = settings
        self.libraryURL = libraryURL
        library = Library.load(from: libraryURL)
        options = OptionsBox(settings.probeOptions)
        alerts = Alerts(settings: settings)
    }

    // MARK: - Counts

    var upCount: Int { probes.filter { $0.status == .up }.count }
    var downCount: Int { probes.filter { $0.status == .down }.count }
    var runningCount: Int { probes.filter(\.isRunning).count }
    var anyRunning: Bool { probes.contains(where: \.isRunning) }

    /// "3 up · 1 down", or what to do next
    var summary: String {
        let running = probes.filter(\.isRunning)
        guard !running.isEmpty else {
            return probes.contains(where: { $0.target != nil }) ? "Stopped" : "Add a host to start"
        }
        var parts: [String] = []
        if upCount > 0 { parts.append("\(upCount) up") }
        let dropping = running.filter { $0.status == .indeterminate }.count
        if dropping > 0 { parts.append("\(dropping) dropping") }
        if downCount > 0 { parts.append("\(downCount) down") }
        let errors = running.filter { if case .error = $0.status { return true } else { return false } }.count
        if errors > 0 { parts.append("\(errors) error\(errors == 1 ? "" : "s")") }
        return parts.isEmpty ? "Starting…" : parts.joined(separator: " · ")
    }

    /// Settings that change how monitors probe take effect on their next probe
    func applyOptions() {
        options.value = settings.probeOptions
    }

    // MARK: - Monitors

    /// A tile, started if it already names a host
    @discardableResult
    func add(_ text: String = "", start: Bool = true) -> Probe {
        let probe = Probe(input: text)
        probe.onStatusChange = { [weak self] probe, old, new in self?.statusChanged(probe, from: old, to: new) }
        probes.append(probe)
        if start, probe.target != nil { self.start(probe) }
        saveSession()
        return probe
    }

    /// Hosts from pasted or dropped text. Fills empty tiles first.
    func addMany(_ text: String) {
        for target in Target.list(from: text) {
            if let empty = probes.first(where: { $0.input.trimmingCharacters(in: .whitespaces).isEmpty && !$0.isRunning }) {
                empty.input = target.text
                start(empty)
            } else {
                add(target.text)
            }
        }
        saveSession()
    }

    /// Replaces every tile with these hosts
    func replaceAll(with hosts: [String], start: Bool = true) {
        for probe in probes where probe.isRunning {
            if let target = probe.target { record(.stop, for: target) }
        }
        probes.forEach { $0.stop(record: false) }
        probes.removeAll()
        hosts.forEach { add($0, start: start) }
        if probes.isEmpty { add() }
        saveSession()
    }

    func remove(_ probe: Probe) {
        if probe.isRunning, let target = probe.target { record(.stop, for: target) }
        probe.stop(record: false)
        probes.removeAll { $0.id == probe.id }
        saveSession()
    }

    func move(_ probe: Probe, before other: Probe) {
        guard probe.id != other.id, let from = probes.firstIndex(where: { $0.id == probe.id }) else { return }
        probes.remove(at: from)
        let to = probes.firstIndex(where: { $0.id == other.id }) ?? probes.count
        probes.insert(probe, at: to)
        saveSession()
    }

    /// One place earlier (-1) or later (1)
    func move(_ probe: Probe, by offset: Int) {
        guard let from = probes.firstIndex(where: { $0.id == probe.id }) else { return }
        let to = from + offset
        guard probes.indices.contains(to) else { return }
        probes.swapAt(from, to)
        saveSession()
    }

    func start(_ probe: Probe) {
        guard probe.start(options: options, downAfter: { [weak self] in self?.settings.downAfter ?? 2 }),
              let target = probe.target else { return }
        record(.start, for: target)
        saveSession()
    }

    func stop(_ probe: Probe) {
        guard probe.isRunning else { return }
        probe.stop()
        if let target = probe.target { record(.stop, for: target) }
    }

    func toggle(_ probe: Probe) {
        probe.isRunning ? stop(probe) : start(probe)
    }

    func retarget(_ probe: Probe, to text: String) {
        let wasRunning = probe.isRunning
        if wasRunning { stop(probe) }
        probe.retarget(text, options: options, downAfter: { [weak self] in self?.settings.downAfter ?? 2 })
        if wasRunning || probe.target != nil { start(probe) }
        saveSession()
    }

    func startAll() {
        for probe in probes where !probe.isRunning && Target(parsing: probe.input) != nil { start(probe) }
    }

    func stopAll() {
        probes.forEach(stop)
    }

    // MARK: - Aliases

    func alias(for target: Target?) -> String? {
        guard let target else { return nil }
        return library.aliases[Library.aliasKey(target.text)] ?? library.aliases[Library.aliasKey(target.host)]
    }

    /// An event with the alias it had then, or the host's alias now
    func withAlias(_ event: StatusEvent) -> StatusEvent {
        guard event.alias == nil, let alias = alias(for: Target(parsing: event.host)) else { return event }
        return StatusEvent(id: event.id, date: event.date, host: event.host, alias: alias, kind: event.kind)
    }

    func setAlias(_ name: String, for host: String) {
        let key = Library.aliasKey(host.trimmingCharacters(in: .whitespaces))
        guard !key.isEmpty else { return }
        let name = name.trimmingCharacters(in: .whitespaces)
        library.aliases[key] = name.isEmpty ? nil : name
        saveLibrary()
    }

    var aliases: [(host: String, name: String)] {
        library.aliases.map { ($0.key, $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Favourites

    var favorites: [Favorite] { library.favorites }

    /// Saves the hosts on screen. Returns false if the name is taken and `replacing` isn't set.
    @discardableResult
    func saveFavorite(named name: String, replacing: Bool = false) -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return false }
        let hosts = probes.compactMap { Target(parsing: $0.input)?.text }
        let favorite = Favorite(name: name, hosts: hosts, columns: columns)
        if let index = library.favorites.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            guard replacing else { return false }
            library.favorites[index] = favorite
        } else {
            library.favorites.append(favorite)
            library.favorites.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        favoriteName = name
        saveLibrary()
        return true
    }

    func updateFavorite(_ old: Favorite, name: String, hosts: [String], columns: Int) {
        guard let index = library.favorites.firstIndex(of: old) else { return }
        let name = name.trimmingCharacters(in: .whitespaces)
        library.favorites[index] = Favorite(name: name, hosts: hosts, columns: columns)
        if settings.startupFavorite == old.name { settings.startupFavorite = name }
        if favoriteName == old.name { favoriteName = name }
        saveLibrary()
    }

    func deleteFavorite(_ favorite: Favorite) {
        library.favorites.removeAll { $0 == favorite }
        if favoriteName == favorite.name { favoriteName = nil }
        if settings.startupFavorite == favorite.name { settings.startupFavorite = nil }
        saveLibrary()
    }

    func load(_ favorite: Favorite) {
        columns = favorite.columns
        replaceAll(with: favorite.hosts)
        favoriteName = favorite.name
    }

    // MARK: - Starting up

    /// Hosts from the command line win, then the startup setting
    func restore(arguments: [String]) {
        let fromCommandLine = Self.hosts(fromArguments: arguments)
        if !fromCommandLine.isEmpty {
            replaceAll(with: fromCommandLine.map(\.text))
            return
        }
        switch settings.startup {
        case .favorite:
            if let name = settings.startupFavorite, let favorite = library.favorites.first(where: { $0.name == name }) {
                load(favorite)
                return
            }
        case .lastSession:
            // Read both first: setting columns saves the (still empty) session
            let hosts = library.lastHosts, lastColumns = library.lastColumns
            if !hosts.isEmpty {
                columns = lastColumns
                replaceAll(with: hosts)
                return
            }
        case .blank:
            break
        }
        replaceAll(with: [], start: false)
        for _ in 1..<max(1, settings.blankCount) { add(start: false) }
    }

    /// Hosts from the command line. `-Key value` pairs (Xcode passes some,
    /// and so can `open --args`) are settings, not hosts.
    nonisolated static func hosts(fromArguments arguments: [String]) -> [Target] {
        var hosts: [Target] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("-psn_") {
                index += 1
            } else if argument.hasPrefix("-") {
                index += 2
            } else {
                if let target = Target(parsing: argument) { hosts.append(target) }
                index += 1
            }
        }
        return hosts
    }

    // MARK: - History and alerts

    private func statusChanged(_ probe: Probe, from old: ProbeStatus, to new: ProbeStatus) {
        guard let target = probe.target else { return }
        switch new {
        case .up where old != .up:
            // Only a host coming back from down is news. Asked before the up is recorded.
            let backUp = old == .down || wasDown(target)
            record(.up, for: target)
            if backUp { alert(probe, up: true) }
        case .down where old != .down:
            record(.down, for: target)
            alert(probe, up: false)
        default:
            break
        }
    }

    /// Whether the last up or down for this host was a down
    private func wasDown(_ target: Target) -> Bool {
        history.last(where: { $0.host == target.text && ($0.kind == .up || $0.kind == .down) })?.kind == .down
    }

    private func alert(_ probe: Probe, up: Bool) {
        guard !quiet, let target = probe.target else { return }
        alerts.post(host: target.text, name: alias(for: target), up: up)
    }

    private func record(_ kind: StatusEvent.Kind, for target: Target) {
        let event = StatusEvent(id: nextEvent, date: Date(), host: target.text, alias: alias(for: target), kind: kind)
        nextEvent += 1
        history.append(event)
        if history.count > Self.maxHistory { history.removeFirst(history.count - Self.maxHistory) }
        if !quiet, kind == .up || kind == .down { alerts.log(event) }
    }

    func clearHistory() { history.removeAll() }

    // MARK: - Saving

    private func saveSession() {
        guard !quiet else { return }
        library.lastHosts = probes.compactMap { Target(parsing: $0.input)?.text }
        library.lastColumns = columns
        saveLibrary()
    }

    private func saveLibrary() {
        guard !quiet else { return }
        library.save(to: libraryURL)
    }

    // MARK: - Demo

    /// Sample monitors for screenshots, with no pinging
    func loadDemo(_ build: (Monitor) -> Void) {
        quiet = true
        probes.removeAll()
        build(self)
    }

    func addDemoProbe(_ probe: Probe) {
        probe.onStatusChange = { [weak self] probe, old, new in self?.statusChanged(probe, from: old, to: new) }
        probes.append(probe)
    }

    func setDemoAliases(_ aliases: [String: String]) {
        library.aliases = aliases
    }

    func setDemoFavorites(_ favorites: [Favorite]) {
        library.favorites = favorites
    }

    func setDemoHistory(_ events: [(minutesAgo: Double, host: String, kind: StatusEvent.Kind)]) {
        history = events.enumerated().map { index, event in
            StatusEvent(id: index, date: Date().addingTimeInterval(-event.minutesAgo * 60), host: event.host,
                        alias: alias(for: Target(parsing: event.host)), kind: event.kind)
        }
        nextEvent = history.count
    }
}

/// Notifications, the alert sound and the status-change log
@MainActor
final class Alerts {
    private let settings: AppSettings
    /// Notifications wait here until macOS says whether they're allowed
    private var waiting: [UNNotificationRequest] = []
    private var asking = false
    private var allowed = false

    init(settings: AppSettings) {
        self.settings = settings
    }

    func post(host: String, name: String?, up: Bool) {
        let label = name.map { "\($0) (\(host))" } ?? host
        if settings.notify { notify(title: "\(label) is \(up ? "up" : "down")",
                                    body: up ? "It's answering again." : "It stopped answering.") }
        if settings.playSound {
            NSSound(named: NSSound.Name(up ? "Glass" : settings.downSound))?.play()
        }
    }

    private func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        if allowed {
            center.add(request)
            return
        }
        waiting.append(request)
        guard !asking else { return }
        asking = true
        // Asked each time until allowed, so turning them on in System Settings works without a restart
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.decided(granted) }
        }
    }

    private func decided(_ granted: Bool) {
        asking = false
        allowed = granted
        if granted { waiting.forEach { UNUserNotificationCenter.current().add($0) } }
        waiting.removeAll()
    }

    /// Appends one line per up or down to the log file, if that's on
    func log(_ event: StatusEvent) {
        guard settings.logToFile else { return }
        let url = URL(fileURLWithPath: (settings.logPath as NSString).expandingTildeInPath)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        var line = "\(formatter.string(from: event.date))  \(event.kind.label.lowercased())  \(event.host)"
        if let alias = event.alias { line += "  (\(alias))" }
        line += "\n"
        let data = Data(line.utf8)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
