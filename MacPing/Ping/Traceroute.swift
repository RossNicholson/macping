import Darwin
import Foundation

/// One router on the way to a host
struct Hop: Identifiable, Equatable, Sendable {
    let number: Int
    /// Nil when nothing answered within the timeout
    var address: String?
    var name: String?
    var ms: Double?
    var reachedTarget = false

    var id: Int { number }
}

/// A fast traceroute: one echo request per hop, sent with a growing TTL, each
/// router on the way answering "time exceeded". Runs on its own thread.
final class Traceroute: @unchecked Sendable {
    enum Event: Sendable {
        case resolved(String)
        case hop(Hop)
        /// The hop's name, looked up after the hop is shown
        case named(hop: Int, name: String)
        case finished(reached: Bool)
        case failed(String)
    }

    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() { lock.withLock { cancelled = true } }

    /// Calls `event` from a background thread as hops come in
    func run(host: String, maxHops: Int = 30, timeout: TimeInterval = 1.5, resolveNames: Bool = true,
             event: @escaping @Sendable (Event) -> Void) {
        Thread.detachNewThread { [self] in
            let address: Address
            do {
                address = try Address.resolve(host)
            } catch {
                event(.failed((error as? PingError)?.message ?? error.localizedDescription))
                return
            }
            event(.resolved(address.text))
            let socket: ICMPSocket
            do {
                socket = try ICMPSocket(family: address.family)
            } catch {
                event(.failed((error as? PingError)?.message ?? error.localizedDescription))
                return
            }
            // Names are looked up alongside, so slow DNS doesn't hold up the hops
            let names = DispatchQueue(label: "MacPing.traceroute.names", attributes: .concurrent)
            for ttl in 1...maxHops {
                if isCancelled { return }
                var hop = Hop(number: ttl)
                var reached = false
                switch socket.ping(address, sequence: UInt16(ttl), timeout: timeout, ttl: ttl) {
                case .reply(let ms, let from, _, _):
                    hop.address = from
                    hop.ms = ms
                    hop.reachedTarget = true
                    reached = true
                case .ttlExpired(let ms, let from):
                    hop.address = from
                    hop.ms = ms
                case .unreachable(let from, _):
                    hop.address = from
                    reached = true
                case .refused, .timedOut, .failed:
                    break
                }
                event(.hop(hop))
                if resolveNames, let from = hop.address, let resolved = try? Address.resolve(from) {
                    names.async {
                        if let name = resolved.reverseName(), name != from { event(.named(hop: ttl, name: name)) }
                    }
                }
                if reached {
                    // Names that are still being looked up arrive afterwards
                    event(.finished(reached: hop.reachedTarget))
                    return
                }
            }
            event(.finished(reached: false))
        }
    }
}
