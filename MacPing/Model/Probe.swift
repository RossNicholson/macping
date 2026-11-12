import Foundation
import Observation

/// How a monitor is doing
enum ProbeStatus: Equatable, Sendable {
    case inactive
    /// Started, nothing back yet
    case waiting
    case up
    /// Lost replies, but not enough yet to call it down
    case indeterminate
    case down
    /// Can't ping at all, e.g. the name doesn't resolve
    case error(String)

    var label: String {
        switch self {
        case .inactive: return "Stopped"
        case .waiting: return "Starting"
        case .up: return "Up"
        case .indeterminate: return "Dropping"
        case .down: return "Down"
        case .error: return "Error"
        }
    }
}

/// One line in a monitor's log
struct ProbeLine: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case reply, lost, error, info }

    let id: Int
    let date: Date
    let text: String
    let kind: Kind
}

/// Running totals for a monitor
struct ProbeStats: Equatable, Sendable {
    var sent = 0
    var received = 0
    var lastMs: Double?
    var minMs: Double?
    var maxMs: Double?
    private var totalMs = 0.0

    var lost: Int { sent - received }
    var lossPercent: Double { sent == 0 ? 0 : Double(lost) / Double(sent) * 100 }
    var averageMs: Double? { received == 0 ? nil : totalMs / Double(received) }

    mutating func record(sent: Bool = true, ms: Double?) {
        if sent { self.sent += 1 }
        guard let ms else { return }
        received += 1
        totalMs += ms
        lastMs = ms
        minMs = min(minMs ?? ms, ms)
        maxMs = max(maxMs ?? ms, ms)
    }
}

/// Settings a running monitor reads before each probe, so changes apply at once
struct ProbeOptions: Sendable, Equatable {
    var interval: TimeInterval = 1
    var timeout: TimeInterval = 2
    var ttl = 64
    var payloadSize = 32
}

/// Shared between the model and the monitors' threads
final class OptionsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ProbeOptions

    init(_ options: ProbeOptions) { stored = options }

    var value: ProbeOptions {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// One host being watched: the tile in the grid
@MainActor
@Observable
final class Probe: Identifiable {
    let id = UUID()
    /// What's typed in the tile
    var input: String
    private(set) var target: Target?
    private(set) var status: ProbeStatus = .inactive
    private(set) var lines: [ProbeLine] = []
    private(set) var stats = ProbeStats()
    private(set) var resolvedAddress: String?
    private(set) var consecutiveLost = 0
    var isRunning: Bool { runner != nil || demoRunning }
    /// Screenshots: shown as running, without pinging
    var demoRunning = false

    /// Called with the old and new status when it changes
    @ObservationIgnored var onStatusChange: ((Probe, ProbeStatus, ProbeStatus) -> Void)?
    @ObservationIgnored private var runner: ProbeRunner?
    @ObservationIgnored private var nextLine = 0
    static let maxLines = 300

    init(input: String = "") {
        self.input = input
        target = Target(parsing: input)
    }

    /// Starts watching what's typed. Returns false if it isn't a host.
    @discardableResult
    func start(options: OptionsBox, downAfter: @escaping @MainActor () -> Int) -> Bool {
        stop(record: false)
        guard let target = Target(parsing: input) else { return false }
        self.target = target
        input = target.text
        stats = ProbeStats()
        consecutiveLost = 0
        resolvedAddress = nil
        lines.removeAll()
        setStatus(.waiting)
        log(target.isPortCheck ? "Checking port \(target.port!) on \(target.host)" : "Pinging \(target.host)", kind: .info)
        let runner = ProbeRunner(target: target, options: options) { [weak self] event in
            Task { @MainActor [weak self] in self?.handle(event, downAfter: downAfter()) }
        }
        self.runner = runner
        runner.start()
        return true
    }

    func stop(record: Bool = true) {
        guard let runner else { return }
        runner.cancel()
        self.runner = nil
        if record { log("Stopped", kind: .info) }
        setStatus(.inactive)
    }

    /// Changes what the tile watches; a running monitor restarts on the new host
    func retarget(_ text: String, options: OptionsBox, downAfter: @escaping @MainActor () -> Int) {
        input = text
        target = Target(parsing: text)
        if isRunning { start(options: options, downAfter: downAfter) }
    }

    private func handle(_ event: ProbeRunner.Event, downAfter: Int) {
        guard runner != nil else { return }   // stopped since
        switch event {
        case .resolved(let address):
            resolvedAddress = address
            if address != target?.host { log("\(target?.host ?? "") is \(address)", kind: .info) }
        case .resolveFailed(let message):
            stats.record(ms: nil)
            log(message, kind: .error)
            setStatus(.error(message))
        case .reply(let reply):
            apply(reply, downAfter: downAfter)
        }
    }

    func apply(_ reply: PingReply, downAfter: Int) {
        let port = target?.port
        switch reply {
        case .reply(let ms, let from, let ttl, let bytes):
            stats.record(ms: ms)
            consecutiveLost = 0
            // The time first: it's what matters, and long lines get cut off
            if let port {
                log("\(Self.format(ms))  port \(port) open on \(from)", kind: .reply)
            } else {
                var text = "\(Self.format(ms))  reply from \(from)"
                if let ttl { text += "  ttl \(ttl)" }
                text += "  \(bytes) bytes"
                log(text, kind: .reply)
            }
            setStatus(.up)
            return
        case .refused(let ms):
            // The host answered, but the port is closed: down for a port check
            stats.record(ms: nil)
            consecutiveLost += 1
            log("\(Self.format(ms))  port \(port ?? 0) closed", kind: .lost)
            setStatus(.down)
            return
        case .timedOut:
            log(port == nil ? "Request timed out" : "Port \(port!) didn't answer", kind: .lost)
        case .unreachable(let from, _):
            log("Destination unreachable (from \(from))", kind: .lost)
        case .ttlExpired(_, let from):
            log("TTL expired in transit (from \(from))", kind: .lost)
        case .failed(let message):
            log(message, kind: .error)
        }
        stats.record(ms: nil)
        consecutiveLost += 1
        setStatus(consecutiveLost >= max(1, downAfter) ? .down : .indeterminate)
    }

    private func setStatus(_ new: ProbeStatus) {
        let old = status
        guard old != new else { return }
        status = new
        onStatusChange?(self, old, new)
    }

    private func log(_ text: String, kind: ProbeLine.Kind) {
        lines.append(ProbeLine(id: nextLine, date: Date(), text: text, kind: kind))
        nextLine += 1
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
    }

    nonisolated static func format(_ ms: Double) -> String {
        ms < 1 ? "<1 ms" : ms < 10 ? String(format: "%.1f ms", ms) : "\(Int(ms.rounded())) ms"
    }
}

/// Probes one target over and over on a thread of its own
final class ProbeRunner: @unchecked Sendable {
    enum Event: Sendable {
        case resolved(String)
        case resolveFailed(String)
        case reply(PingReply)
    }

    private let target: Target
    private let options: OptionsBox
    private let send: @Sendable (Event) -> Void
    private let lock = NSLock()
    private var cancelled = false
    /// Names are looked up again now and then, in case they move
    private static let reresolveEvery: TimeInterval = 60

    init(target: Target, options: OptionsBox, send: @escaping @Sendable (Event) -> Void) {
        self.target = target
        self.options = options
        self.send = send
    }

    private var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() { lock.withLock { cancelled = true } }

    func start() {
        let thread = Thread { [self] in loop() }
        thread.name = "MacPing \(target.text)"
        thread.qualityOfService = .utility
        thread.start()
    }

    private func loop() {
        var address: Address?
        var socket: ICMPSocket?
        var resolvedAt = Date.distantPast
        var lastAddress: String?
        var sequence: UInt16 = 0

        while !isCancelled {
            let started = Date()
            let options = options.value

            if let port = target.port {
                send(.reply(TCPCheck.check(host: target.host, port: port, timeout: options.timeout)))
            } else {
                if address == nil || started.timeIntervalSince(resolvedAt) > Self.reresolveEvery {
                    do {
                        let found = try Address.resolve(target.host)
                        if found.family != address?.family { socket = try ICMPSocket(family: found.family) }
                        address = found
                        resolvedAt = started
                        if found.text != lastAddress {
                            lastAddress = found.text
                            send(.resolved(found.text))
                        }
                    } catch {
                        address = nil
                        send(.resolveFailed(error.message))
                    }
                }
                if let address, let socket {
                    sequence &+= 1
                    let reply = socket.ping(address, sequence: sequence, timeout: options.timeout,
                                            ttl: options.ttl, payloadSize: options.payloadSize)
                    if isCancelled { return }
                    send(.reply(reply))
                }
            }

            // Wait out the rest of the interval, checking for a stop now and then
            let next = started.addingTimeInterval(options.interval)
            while !isCancelled, Date() < next {
                Thread.sleep(forTimeInterval: min(0.1, max(0, next.timeIntervalSinceNow)))
            }
        }
    }
}
