import Foundation
import Network

/// A TCP "port ping": connects to the port and closes again, timing the handshake.
/// An answer of any kind, even a refusal, means the host is there; only a
/// connection that's accepted counts as the port being up.
enum TCPCheck {
    /// Blocks for up to `timeout`
    static func check(host: String, port: UInt16, timeout: TimeInterval) -> PingReply {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return .failed("Not a port") }
        let parameters = NWParameters.tcp
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.connectionTimeout = max(1, Int(timeout.rounded(.up)))
            tcp.noDelay = true
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        let outcome = Outcome()
        let done = DispatchSemaphore(value: 0)
        let start = DispatchTime.now()
        let queue = DispatchQueue(label: "MacPing.tcp")

        connection.stateUpdateHandler = { state in
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            switch state {
            case .ready:
                let remote = connection.currentPath?.remoteEndpoint.map(Self.describe) ?? host
                outcome.set(.reply(ms: ms, from: remote, ttl: nil, bytes: 0))
                done.signal()
            case .waiting(let error), .failed(let error):
                outcome.set(Self.reply(for: error, ms: ms))
                done.signal()
            default:
                break
            }
        }
        connection.start(queue: queue)
        let result: PingReply = done.wait(timeout: .now() + timeout) == .timedOut ? .timedOut : (outcome.value ?? .timedOut)
        connection.stateUpdateHandler = nil
        connection.cancel()
        return result
    }

    static func reply(for error: NWError, ms: Double) -> PingReply {
        switch error {
        case .posix(.ECONNREFUSED): return .refused(ms: ms)
        case .posix(.ETIMEDOUT): return .timedOut
        case .dns: return .failed(PingError.unknownHost.message)
        case .posix(let code): return .failed(String(cString: strerror(code.rawValue)))
        default: return .failed(error.localizedDescription)
        }
    }

    private static func describe(_ endpoint: NWEndpoint) -> String {
        if case .hostPort(let host, _) = endpoint {
            switch host {
            case .ipv4(let address): return "\(address)"
            case .ipv6(let address): return "\(address)"
            case .name(let name, _): return name
            @unknown default: return "\(host)"
            }
        }
        return "\(endpoint)"
    }

    /// Set once by the connection's queue, read after the wait
    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: PingReply?

        var value: PingReply? { lock.withLock { stored } }

        func set(_ reply: PingReply) {
            lock.withLock { if stored == nil { stored = reply } }
        }
    }
}
