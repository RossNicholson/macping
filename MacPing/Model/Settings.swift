import Foundation
import Observation
import ServiceManagement

/// What MacPing shows when it opens
enum StartupMode: String, CaseIterable, Sendable {
    /// Empty tiles to type hosts into
    case blank
    /// The hosts from last time, started again
    case lastSession
    /// A saved favourite set
    case favorite

    var label: String {
        switch self {
        case .blank: return "Blank"
        case .lastSession: return "Last hosts"
        case .favorite: return "A favourite"
        }
    }
}

/// User settings, kept in UserDefaults. Tests pass their own defaults.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?

    static let intervals: [TimeInterval] = [0.5, 1, 2, 5, 10]
    static let timeouts: [TimeInterval] = [0.5, 1, 2, 5]
    static let downAfterChoices = [1, 2, 3, 5]
    static let sounds = ["Basso", "Funk", "Glass", "Ping", "Sosumi", "Submarine"]

    var interval: TimeInterval { didSet { save(interval, Keys.interval) } }
    var timeout: TimeInterval { didSet { save(timeout, Keys.timeout) } }
    var ttl: Int { didSet { save(ttl, Keys.ttl) } }
    var payloadSize: Int { didSet { save(payloadSize, Keys.payloadSize) } }
    /// Lost replies in a row before a host counts as down
    var downAfter: Int { didSet { save(downAfter, Keys.downAfter) } }
    var notify: Bool { didSet { save(notify, Keys.notify) } }
    var playSound: Bool { didSet { save(playSound, Keys.playSound) } }
    var downSound: String { didSet { save(downSound, Keys.downSound) } }
    var logToFile: Bool { didSet { save(logToFile, Keys.logToFile) } }
    var logPath: String { didSet { save(logPath, Keys.logPath) } }
    var alwaysOnTop: Bool { didSet { save(alwaysOnTop, Keys.alwaysOnTop); onChange?() } }
    var showInMenuBar: Bool { didSet { save(showInMenuBar, Keys.showInMenuBar); onChange?() } }
    var startup: StartupMode { didSet { save(startup.rawValue, Keys.startup) } }
    var startupFavorite: String? { didSet { save(startupFavorite, Keys.startupFavorite) } }
    var blankCount: Int { didSet { save(blankCount, Keys.blankCount) } }

    enum Keys {
        static let interval = "interval"
        static let timeout = "timeout"
        static let ttl = "ttl"
        static let payloadSize = "payloadSize"
        static let downAfter = "downAfter"
        static let notify = "notify"
        static let playSound = "playSound"
        static let downSound = "downSound"
        static let logToFile = "logToFile"
        static let logPath = "logPath"
        static let alwaysOnTop = "alwaysOnTop"
        static let showInMenuBar = "showInMenuBar"
        static let startup = "startup"
        static let startupFavorite = "startupFavorite"
        static let blankCount = "blankCount"
    }

    static var defaultLogPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacPing/Status changes.log").path
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        interval = defaults.object(forKey: Keys.interval) as? Double ?? 1
        timeout = defaults.object(forKey: Keys.timeout) as? Double ?? 2
        ttl = defaults.object(forKey: Keys.ttl) as? Int ?? 64
        payloadSize = defaults.object(forKey: Keys.payloadSize) as? Int ?? 32
        downAfter = defaults.object(forKey: Keys.downAfter) as? Int ?? 2
        notify = defaults.object(forKey: Keys.notify) as? Bool ?? true
        playSound = defaults.object(forKey: Keys.playSound) as? Bool ?? true
        downSound = defaults.string(forKey: Keys.downSound) ?? "Basso"
        logToFile = defaults.bool(forKey: Keys.logToFile)
        logPath = defaults.string(forKey: Keys.logPath) ?? Self.defaultLogPath
        alwaysOnTop = defaults.bool(forKey: Keys.alwaysOnTop)
        showInMenuBar = defaults.object(forKey: Keys.showInMenuBar) as? Bool ?? true
        startup = defaults.string(forKey: Keys.startup).flatMap(StartupMode.init) ?? .blank
        startupFavorite = defaults.string(forKey: Keys.startupFavorite)
        blankCount = defaults.object(forKey: Keys.blankCount) as? Int ?? 4
    }

    var probeOptions: ProbeOptions {
        ProbeOptions(interval: interval, timeout: min(timeout, max(interval, 0.5) * 5),
                     ttl: ttl, payloadSize: payloadSize)
    }

    private func save(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
    }

    // MARK: - Launch at login

    /// Set by SMAppService; read back from it so it matches System Settings
    private(set) var openAtLoginEnabled = AppSettings.openAtLogin
    private(set) var loginError: String?

    nonisolated static var openAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "macOS didn't allow that: \(error.localizedDescription)"
        }
        openAtLoginEnabled = Self.openAtLogin
    }
}
